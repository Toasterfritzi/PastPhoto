import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers
import AVFoundation

@MainActor
class PastPhotoViewModel: ObservableObject {
    // ── User Input ──
    @Published var experimentalMode: Bool = false
    @Published var selectedVideoItem: PhotosPickerItem? = nil {
        didSet { loadSelectedVideo() }
    }
    
    // ── Trim & Frame ──
    @Published var keyFramePercent: Double = 0.5
    @Published var trimStart: Double = 0.0
    @Published var trimEnd: Double = 2.5
    @Published var videoDuration: Double? = nil
    
    // ── Playback ──
    @Published var bounceMode: Bool = false
    @Published var playbackSpeed: PlaybackSpeed = .normal
    
    // ── Aspect Ratio ──
    @Published var aspectRatio: AspectRatio = .original
    
    // ── Gooner ──
    @Published var goonerMode: Bool = false
    
    // ── State ──
    @Published var selectedVideoName: String? = nil
    @Published var isProcessing: Bool = false
    @Published var isComplete: Bool = false
    @Published var statusMessage: String = ""
    @Published var errorMessage: String? = nil
    
    // ── Saved Asset ──
    @Published var savedAssetIdentifier: String? = nil
    
    // ── Internal ──
    private var selectedVideoURL: URL? = nil

    var canConvert: Bool {
        selectedVideoURL != nil && !isProcessing
    }
    
    /// Maximum allowed duration based on experimental mode
    var effectiveTrimEnd: Double {
        guard let dur = videoDuration else { return trimEnd }
        if experimentalMode {
            return min(trimEnd, dur)
        } else {
            return min(trimEnd, min(dur, 2.5))
        }
    }

    // MARK: - Video Loading

    private func loadSelectedVideo() {
        guard let item = selectedVideoItem else { return }

        selectedVideoURL = nil
        selectedVideoName = "Video wird geladen..."
        print("[PastPhoto] 📂 Video wird aus Fotos-App geladen...")

        item.loadTransferable(type: VideoTransferable.self) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let video):
                    if let video = video {
                        self?.selectedVideoURL = video.url
                        self?.selectedVideoName = video.url.lastPathComponent
                        print("[PastPhoto] ✅ Video geladen: \(video.url.lastPathComponent)")
                        
                        // Load video duration for sliders
                        await self?.loadVideoDuration(from: video.url)
                    } else {
                        self?.selectedVideoURL = nil
                        self?.selectedVideoName = nil
                        self?.errorMessage = "Video konnte nicht geladen werden."
                    }
                case .failure(let error):
                    self?.selectedVideoURL = nil
                    self?.selectedVideoName = nil
                    self?.errorMessage = "Video-Ladefehler: \(error.localizedDescription)"
                    print("[PastPhoto] ❌ Transferable fehlgeschlagen: \(error)")
                }
            }
        }
    }
    
    /// Loads the duration of the selected video for slider ranges.
    private func loadVideoDuration(from url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            videoDuration = seconds
            trimStart = 0.0
            trimEnd = experimentalMode ? seconds : min(seconds, 2.5)
            print("[PastPhoto] ⏱️ Video-Dauer geladen: \(String(format: "%.1f", seconds))s")
        } catch {
            print("[PastPhoto] ⚠️ Dauer konnte nicht geladen werden: \(error)")
        }
    }

    // MARK: - Process & Save

    func convertAndSave() async {
        guard let videoURL = selectedVideoURL else {
            print("[PastPhoto] ❌ Kein Video ausgewählt")
            return
        }

        isProcessing = true
        isComplete = false
        errorMessage = nil
        savedAssetIdentifier = nil

        print("[PastPhoto] 🚀 Starte Verarbeitung...")
        print("[PastPhoto] 🧪 Experimentell: \(experimentalMode)")
        print("[PastPhoto] 🐸 Gooner: \(goonerMode)")
        print("[PastPhoto] ⚡ Speed: \(playbackSpeed.label)")
        print("[PastPhoto] 📐 Ratio: \(aspectRatio.rawValue)")

        do {
            let assetIdentifier = UUID().uuidString
            
            // Step 1: Export Video
            statusMessage = "Video wird verarbeitet..."
            print("[PastPhoto] ⬇️ Schritt 1/3: Video exportieren...")
            
            let movURL = try await MediaProcessor.exportVideo(
                from: videoURL,
                trimStart: trimStart,
                trimEnd: effectiveTrimEnd,
                assetIdentifier: assetIdentifier,
                playbackSpeed: playbackSpeed.rawValue,
                aspectRatio: aspectRatio,
                goonerMode: goonerMode
            )
            print("[PastPhoto] ✅ MOV erstellt: \(movURL.lastPathComponent)")

            // Step 2: Extract Key Photo
            statusMessage = goonerMode ? "Key Photo wird frittiert... 🐸" : "Key Photo wird generiert..."
            print("[PastPhoto] ⬇️ Schritt 2/3: Key Photo extrahieren...")
            
            let jpegURL = try await MediaProcessor.generateKeyPhoto(
                from: movURL,
                at: keyFramePercent,
                assetIdentifier: assetIdentifier,
                aspectRatio: aspectRatio,
                goonerMode: goonerMode
            )
            print("[PastPhoto] ✅ HEIC erstellt: \(jpegURL.lastPathComponent)")

            // Step 3: Save as Live Photo
            statusMessage = "Speichere in Fotos-App..."
            print("[PastPhoto] 💾 Schritt 3/3: Speichere Live Photo...")

            let assetId = try await LivePhotoSaver.save(
                imageURL: jpegURL,
                videoURL: movURL,
                bounceMode: bounceMode
            )
            
            savedAssetIdentifier = assetId

            // Cleanup Temp Files
            try? FileManager.default.removeItem(at: jpegURL)
            try? FileManager.default.removeItem(at: movURL)

            print("[PastPhoto] 🎉 FERTIG! Live Photo in der Fotos-App gespeichert!")
            
            // Show success UI
            withAnimation(.spring(duration: 0.5)) {
                isComplete = true
                isProcessing = false
            }

        } catch {
            withAnimation {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
            print("[PastPhoto] ❌ FEHLER: \(error)")
        }
    }
    
    // MARK: - Wallpaper
    
    /// Opens a share sheet for the saved Live Photo so the user can set it as wallpaper.
    func shareForWallpaper() {
        guard let assetId = savedAssetIdentifier else { return }
        
        // Try to open the Photos app to the saved asset
        // The user can then long-press → "Use as Wallpaper"
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Actions

    func clearSelection() {
        selectedVideoItem = nil
        selectedVideoName = nil
        selectedVideoURL = nil
        videoDuration = nil
        trimStart = 0.0
        trimEnd = 2.5
    }

    func reset() {
        clearSelection()
        isComplete = false
        isProcessing = false
        errorMessage = nil
        statusMessage = ""
        savedAssetIdentifier = nil
        keyFramePercent = 0.5
        playbackSpeed = .normal
        aspectRatio = .original
        goonerMode = false
        bounceMode = false
    }
}

// MARK: - Video Transferable
// Copies the video file to a temp location so we hold a stable URL

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let dest = tempDir.appendingPathComponent(
                "video_\(UUID().uuidString).\(received.file.pathExtension)"
            )
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            print("[PastPhoto] 📂 Video kopiert nach: \(dest.lastPathComponent)")
            return Self(url: dest)
        }
    }
}

// MARK: - Errors

enum PastPhotoError: LocalizedError {
    case exportFailed(String)
    case frameExtractionFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .exportFailed(let msg): return "Video-Export fehlgeschlagen: \(msg)"
        case .frameExtractionFailed: return "Key Photo konnte nicht extrahiert werden."
        case .notAuthorized: return "Fotos-Zugriff verweigert. Bitte in den Einstellungen erlauben."
        }
    }
}
