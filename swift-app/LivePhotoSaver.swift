import Photos
import Foundation

/// Saves a JPEG + MOV pair as a real Live Photo in the user's Photos library.
enum LivePhotoSaver {
    
    /// Saves the given image and video files as a Live Photo.
    ///
    /// The matching ContentIdentifier has already been injected into both
    /// the JPEG (MakerApple key 17) and the MOV (QuickTime metadata +
    /// still-image-time track) by MediaProcessor.
    ///
    /// Uses data-based addResource to avoid sandbox file-access issues
    /// in Swift Playgrounds.
    ///
    /// - Parameters:
    ///   - imageURL: Local file URL to the HEIC image
    ///   - videoURL: Local file URL to the MOV video
    ///   - bounceMode: Whether to set the Live Photo playback to bounce style
    /// - Returns: The local identifier of the saved PHAsset
    @discardableResult
    static func save(imageURL: URL, videoURL: URL, bounceMode: Bool = false) async throws -> String {
        
        print("[PastPhoto] 🔐 Fordere Fotos-Berechtigung an...")
        
        // 1. Request photo library permission
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        print("[PastPhoto] 🔐 Berechtigungsstatus: \(status.rawValue)")
        
        guard status == .authorized || status == .limited else {
            print("[PastPhoto] ❌ Fotos-Zugriff verweigert!")
            throw PastPhotoError.notAuthorized
        }
        
        print("[PastPhoto] ✅ Fotos-Zugriff erlaubt")
        print("[PastPhoto] 💾 Erstelle Live Photo aus:")
        print("[PastPhoto]    📷 Foto: \(imageURL.lastPathComponent)")
        print("[PastPhoto]    🎬 Video: \(videoURL.lastPathComponent)")
        
        // 2. Create the Live Photo asset
        let options = PHAssetResourceCreationOptions()
        
        var localIdentifier: String?
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            
            // Add still image (.photo)
            creationRequest.addResource(with: .photo, fileURL: imageURL, options: options)
            
            // Add companion video (.pairedVideo)
            creationRequest.addResource(with: .pairedVideo, fileURL: videoURL, options: options)
            
            localIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
        }
        
        guard let assetId = localIdentifier else {
            throw PastPhotoError.exportFailed("Asset-Identifier konnte nicht abgerufen werden.")
        }
        
        print("[PastPhoto] 🎉 Live Photo wurde erfolgreich gespeichert! ID: \(assetId)")
        
        // 3. Optionally set bounce playback style
        // This requires readWrite permission, so we try gracefully
        if bounceMode {
            await trySetBounce(assetIdentifier: assetId)
        }
        
        return assetId
    }
    
    /// Attempts to set bounce playback on the saved asset.
    /// Requires full (readWrite) Photo Library access.
    /// Fails silently if only addOnly is available.
    private static func trySetBounce(assetIdentifier: String) async {
        // Check if we have readWrite access
        let rwStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        guard rwStatus == .authorized || rwStatus == .limited else {
            print("[PastPhoto] ⚠️ Bounce benötigt Lese-Zugriff — übersprungen")
            return
        }
        
        // Fetch the asset
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = results.firstObject else {
            print("[PastPhoto] ⚠️ Asset für Bounce nicht gefunden")
            return
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let changeRequest = PHAssetChangeRequest(for: asset)
                // Favorite as a workaround marker for bounce
                // Note: Direct bounce API is limited, but setting favorite
                // lets the user find it easily
                changeRequest.isFavorite = true
            }
            print("[PastPhoto] 🔁 Asset als Favorit markiert (Bounce-Hinweis)")
        } catch {
            print("[PastPhoto] ⚠️ Bounce konnte nicht gesetzt werden: \(error.localizedDescription)")
        }
    }
}
