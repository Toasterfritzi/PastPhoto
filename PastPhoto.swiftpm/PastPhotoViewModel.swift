import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

@MainActor
class PastPhotoViewModel: ObservableObject {
    // ── User Input ──
    @Published var experimentalMode: Bool = false
    @Published var selectedVideoItem: PhotosPickerItem? = nil {
        didSet { loadSelectedVideo() }
    }

    // ── State ──
    @Published var selectedVideoName: String? = nil
    @Published var isProcessing: Bool = false
    @Published var isComplete: Bool = false
    @Published var statusMessage: String = ""
    @Published var errorMessage: String? = nil

    // ── Internal ──
    private var selectedVideoURL: URL? = nil

    var canConvert: Bool {
        selectedVideoURL != nil && !isProcessing
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

    // MARK: - Process & Save Locally

    func convertAndSave() async {
        guard let videoURL = selectedVideoURL else {
            print("[PastPhoto] ❌ Kein Video ausgewählt")
            return
        }

        isProcessing = true
        isComplete = false
        errorMessage = nil

        print("[PastPhoto] 🚀 Starte lokale Verarbeitung...")
        print("[PastPhoto] 🧪 Experimentell: \(experimentalMode)")

        do {
            let assetIdentifier = UUID().uuidString
            
            // Step 1: Export Video (MOV, trimmed to 2.5s if not experimental)
            statusMessage = "Video wird formatiert & getrimmt..."
            print("[PastPhoto] ⬇️ Schritt 1/3: Video exportieren...")
            
            let maxDuration: Double? = experimentalMode ? nil : 2.5
            let movURL = try await MediaProcessor.exportVideo(from: videoURL, maxDuration: maxDuration, assetIdentifier: assetIdentifier)
            print("[PastPhoto] ✅ MOV erstellt: \(movURL.lastPathComponent)")

            // Step 2: Extract Key Photo (JPEG)
            statusMessage = "Key Photo wird generiert..."
            print("[PastPhoto] ⬇️ Schritt 2/3: JPEG extrahieren...")
            
            let jpegURL = try await MediaProcessor.generateKeyPhoto(from: movURL, at: 0.5, assetIdentifier: assetIdentifier)
            print("[PastPhoto] ✅ JPEG erstellt: \(jpegURL.lastPathComponent)")

            // Step 3: Save as Live Photo
            statusMessage = "Speichere in Fotos-App..."
            print("[PastPhoto] 💾 Schritt 3/3: Speichere Live Photo...")

            try await LivePhotoSaver.save(imageURL: jpegURL, videoURL: movURL)

            // Cleanup Temp Files
            try? FileManager.default.removeItem(at: jpegURL)
            try? FileManager.default.removeItem(at: movURL)

            print("[PastPhoto] 🎉 FERTIG! Live Photo in der Fotos-App gespeichert!")
            
            // Show success UI
            withAnimation {
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

    // MARK: - Actions

    func clearSelection() {
        selectedVideoItem = nil
        selectedVideoName = nil
        selectedVideoURL = nil
    }

    func reset() {
        clearSelection()
        isComplete = false
        isProcessing = false
        errorMessage = nil
        statusMessage = ""
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
