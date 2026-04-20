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
    ///   - imageURL: Local file URL to the JPEG image
    ///   - videoURL: Local file URL to the MOV video
    static func save(imageURL: URL, videoURL: URL) async throws {
        
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
        
        // 2. Add resources using file URLs
        // Note: We MUST use fileURL for video, as passing video as Data is unsupported
        // and causes PHPhotosErrorDomain 3300.
        
        let options = PHAssetResourceCreationOptions()
        // We let the system copy the files, so we don't use shouldMoveFile
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            
            // Add still image (.photo)
            creationRequest.addResource(with: .photo, fileURL: imageURL, options: options)
            
            // Add companion video (.pairedVideo)
            creationRequest.addResource(with: .pairedVideo, fileURL: videoURL, options: options)
        }
        
        print("[PastPhoto] 🎉 Live Photo wurde erfolgreich gespeichert!")
    }
}
