import Foundation
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

// MARK: - Enums

enum AspectRatio: String, CaseIterable, Hashable {
    case original = "Original"
    case portrait = "9:16"
    case fourThree = "4:3"
    case square = "1:1"
}

enum PlaybackSpeed: Double, CaseIterable, Hashable {
    case quarter = 0.25
    case half = 0.5
    case normal = 1.0
    case oneHalf = 1.5
    case double = 2.0
    
    var label: String {
        switch self {
        case .quarter: return "0.25x"
        case .half: return "0.5x"
        case .normal: return "1x"
        case .oneHalf: return "1.5x"
        case .double: return "2x"
        }
    }
}

/// Handles all local AVFoundation video processing (trimming, exporting, frame extraction).
enum MediaProcessor {
    
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // MARK: - Crop Calculation
    
    /// Calculates the center-crop rect for a given size and target aspect ratio.
    static func cropRect(for size: CGSize, ratio: AspectRatio) -> CGRect {
        guard ratio != .original else { return CGRect(origin: .zero, size: size) }
        
        let targetRatio: CGFloat
        switch ratio {
        case .portrait: targetRatio = 9.0 / 16.0
        case .fourThree: targetRatio = 3.0 / 4.0
        case .square: targetRatio = 1.0
        case .original: targetRatio = size.width / size.height
        }
        
        let currentRatio = size.width / size.height
        if currentRatio > targetRatio {
            // Wider than target → crop sides
            let newWidth = size.height * targetRatio
            let x = (size.width - newWidth) / 2
            return CGRect(x: x, y: 0, width: newWidth, height: size.height)
        } else {
            // Taller than target → crop top/bottom
            let newHeight = size.width / targetRatio
            let y = (size.height - newHeight) / 2
            return CGRect(x: 0, y: y, width: size.width, height: newHeight)
        }
    }
    
    // MARK: - Video Export
    
    /// Exportiert das Video als QuickTime MOV mit eingebettetem Content Identifier.
    /// Nutzt AVAssetWriter statt AVAssetExportSession, damit die Live-Photo-Metadaten
    /// (Content Identifier + Still Image Time) korrekt in die Datei geschrieben werden.
    ///
    /// Supports: trimming, speed adjustment, aspect ratio cropping, and gooner mode effects.
    static func exportVideo(
        from sourceURL: URL,
        trimStart: Double,
        trimEnd: Double?,
        assetIdentifier: String,
        playbackSpeed: Double = 1.0,
        aspectRatio: AspectRatio = .original,
        goonerMode: Bool = false
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        
        // Dauer asynchron laden
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        print("[PastPhoto] 🎬 Video-Dauer: \(String(format: "%.1f", durationSeconds))s")
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastphoto_\(UUID().uuidString).mov")
        
        // Falls Datei existiert, löschen
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // ── Trim-Bereich berechnen ──
        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endSeconds = min(trimEnd ?? durationSeconds, durationSeconds)
        let endTime = CMTime(seconds: endSeconds, preferredTimescale: 600)
        let trimmedDuration = CMTimeSubtract(endTime, startTime)
        
        // ── Speed: AVMutableComposition ──
        let composition = AVMutableComposition()
        
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw PastPhotoError.exportFailed("Keine Video-Spur gefunden.")
        }
        
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PastPhotoError.exportFailed("Konnte Kompositions-Videospur nicht erstellen.")
        }
        
        let trimRange = CMTimeRange(start: startTime, end: endTime)
        try compVideoTrack.insertTimeRange(trimRange, of: sourceVideoTrack, at: .zero)
        
        // Preserve transform
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        compVideoTrack.preferredTransform = transform
        
        // Audio track (optional)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var hasAudio = false
        if let sourceAudioTrack = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compAudioTrack.insertTimeRange(trimRange, of: sourceAudioTrack, at: .zero)
            hasAudio = true
        }
        
        // Apply speed
        if playbackSpeed != 1.0 {
            let compositionRange = CMTimeRange(start: .zero, duration: trimmedDuration)
            let scaledDuration = CMTimeMultiplyByFloat64(trimmedDuration, multiplier: 1.0 / playbackSpeed)
            composition.scaleTimeRange(compositionRange, toDuration: scaledDuration)
            print("[PastPhoto] ⚡ Geschwindigkeit: \(playbackSpeed)x")
        }
        
        print("[PastPhoto] ✂️ Trim: \(String(format: "%.1f", trimStart))s → \(String(format: "%.1f", endSeconds))s")
        
        // ── Finale Dauer nach Speed ──
        let finalDuration = CMTimeGetSeconds(composition.duration)
        
        // ── AVAssetReader einrichten (liest aus der Composition) ──
        let reader = try AVAssetReader(asset: composition)
        
        let compVideoTracks = try await composition.loadTracks(withMediaType: .video)
        guard let readVideoTrack = compVideoTracks.first else {
            throw PastPhotoError.exportFailed("Keine Video-Spur in Composition.")
        }
        
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: readVideoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        reader.add(videoReaderOutput)
        
        var audioReaderOutput: AVAssetReaderTrackOutput? = nil
        if hasAudio {
            let compAudioTracks = try await composition.loadTracks(withMediaType: .audio)
            if let readAudioTrack = compAudioTracks.first {
                let aOutput = AVAssetReaderTrackOutput(track: readAudioTrack, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1
                ])
                reader.add(aOutput)
                audioReaderOutput = aOutput
            }
        }
        
        // ── Video-Dimensionen mit Aspect-Ratio Crop ──
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let isPortrait = transform.a == 0 && transform.d == 0
        let rawWidth = isPortrait ? abs(naturalSize.height) : abs(naturalSize.width)
        let rawHeight = isPortrait ? abs(naturalSize.width) : abs(naturalSize.height)
        let rawSize = CGSize(width: rawWidth, height: rawHeight)
        
        let crop = cropRect(for: rawSize, ratio: aspectRatio)
        let videoWidth = crop.width
        let videoHeight = crop.height
        
        if aspectRatio != .original {
            print("[PastPhoto] 📐 Aspect Ratio Crop: \(Int(videoWidth))×\(Int(videoHeight))")
        }
        
        // ── AVAssetWriter einrichten ──
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Content Identifier Metadaten setzen
        let contentIdItem = AVMutableMetadataItem()
        contentIdItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as (NSCopying & NSObjectProtocol)
        contentIdItem.keySpace = .quickTimeMetadata
        contentIdItem.value = assetIdentifier as (NSCopying & NSObjectProtocol)
        contentIdItem.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [contentIdItem]
        
        // Video-Bitrate: extrem niedrig im Gooner-Modus für maximale Blockartifakte
        let videoBitRate = goonerMode ? 250_000 : 6_000_000
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoWriterInput.transform = (aspectRatio == .original) ? transform : .identity
        videoWriterInput.expectsMediaDataInRealTime = false
        writer.add(videoWriterInput)
        
        // Pixel Buffer Adaptor (needed for frame processing)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(videoWidth),
                kCVPixelBufferHeightKey as String: Int(videoHeight)
            ]
        )
        
        // Audio Writer Input (optional)
        var audioWriterInput: AVAssetWriterInput? = nil
        if audioReaderOutput != nil {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ])
            aInput.expectsMediaDataInRealTime = false
            writer.add(aInput)
            audioWriterInput = aInput
        }
        
        // ── Still Image Time Metadata Track ──
        // Dieser Track signalisiert dem System, welcher Frame das Standbild ist.
        let metadataSpec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String
        ]
        
        var formatDesc: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [metadataSpec] as CFArray,
            formatDescriptionOut: &formatDesc
        )
        
        if let formatDesc = formatDesc {
            let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: formatDesc)
            let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
            writer.add(metadataInput)
            
            // Starten
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            // Still Image Time bei der Mitte schreiben
            let stillTime = CMTime(seconds: finalDuration / 2.0, preferredTimescale: 600)
            let stillItem = AVMutableMetadataItem()
            stillItem.key = "com.apple.quicktime.still-image-time" as (NSCopying & NSObjectProtocol)
            stillItem.keySpace = .quickTimeMetadata
            stillItem.value = 0 as (NSCopying & NSObjectProtocol)
            stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
            
            let timedGroup = AVTimedMetadataGroup(
                items: [stillItem],
                timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: 600))
            )
            metadataAdaptor.append(timedGroup)
        } else {
            // Fallback ohne Metadata Track
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
        }
        
        // ── Flags für Processing ──
        let needsFrameProcessing = (aspectRatio != .original) || goonerMode
        
        // ── Video und Audio Samples parallel kopieren ──
        await withTaskGroup(of: Void.self) { group in
            // Video-Task
            group.addTask {
                nonisolated(unsafe) let safeVideoInput = videoWriterInput
                nonisolated(unsafe) let safeVideoOutput = videoReaderOutput
                nonisolated(unsafe) let safeAdaptor = pixelBufferAdaptor
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    safeVideoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.write")) {
                        while safeVideoInput.isReadyForMoreMediaData {
                            guard let sampleBuffer = safeVideoOutput.copyNextSampleBuffer() else {
                                safeVideoInput.markAsFinished()
                                continuation.resume()
                                return
                            }
                            
                            if needsFrameProcessing {
                                // Process frame: crop + gooner effects
                                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                                    continue
                                }
                                
                                var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                                
                                // Apply crop if needed
                                if aspectRatio != .original {
                                    // Map crop rect to pixel buffer coordinates (may be in raw orientation)
                                    let pbWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                                    let pbHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                                    let pbSize = CGSize(width: pbWidth, height: pbHeight)
                                    let pbCrop = cropRect(for: pbSize, ratio: aspectRatio)
                                    ciImage = ciImage.cropped(to: pbCrop)
                                    ciImage = ciImage.transformed(by: CGAffineTransform(
                                        translationX: -pbCrop.origin.x,
                                        y: -pbCrop.origin.y
                                    ))
                                }
                                
                                // Apply gooner effects
                                if goonerMode {
                                    ciImage = GoonerEffects.deepFry(ciImage)
                                }
                                
                                // Render to new pixel buffer
                                guard let pool = safeAdaptor.pixelBufferPool else { continue }
                                var newBuffer: CVPixelBuffer?
                                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &newBuffer)
                                guard let outBuffer = newBuffer else { continue }
                                
                                MediaProcessor.ciContext.render(ciImage, to: outBuffer)
                                safeAdaptor.append(outBuffer, withPresentationTime: pts)
                            } else {
                                // Direct pass-through
                                safeVideoInput.append(sampleBuffer)
                            }
                        }
                    }
                }
            }
            
            // Audio-Task
            if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
                group.addTask {
                    nonisolated(unsafe) let safeAudioInput = audioInput
                    nonisolated(unsafe) let safeAudioOutput = audioOutput
                    
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        safeAudioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.write")) {
                            while safeAudioInput.isReadyForMoreMediaData {
                                guard let sampleBuffer = safeAudioOutput.copyNextSampleBuffer() else {
                                    safeAudioInput.markAsFinished()
                                    continuation.resume()
                                    return
                                }
                                
                                // Apply audio distortion in gooner mode
                                if goonerMode {
                                    GoonerEffects.distortAudio(sampleBuffer)
                                }
                                
                                safeAudioInput.append(sampleBuffer)
                            }
                        }
                    }
                }
            }
        }
        
        // ── Finalisieren ──
        await writer.finishWriting()
        reader.cancelReading()
        
        guard writer.status == .completed else {
            let errorMsg = writer.error?.localizedDescription ?? "Unbekannter Fehler beim Schreiben"
            throw PastPhotoError.exportFailed(errorMsg)
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("[PastPhoto] ✅ MOV erfolgreich exportiert. Dateigröße: \(fileSize / 1024) KB")
        
        return outputURL
    }
    
    // MARK: - Key Photo Extraction
    
    /// Extrahiert asynchron einen Frame aus dem Video und speichert ihn als HEIC.
    /// Fügt den `assetIdentifier` via CGImageDestination ein.
    /// Supports aspect ratio cropping and gooner mode effects.
    static func generateKeyPhoto(
        from videoURL: URL,
        at timePercent: Double = 0.5,
        assetIdentifier: String,
        aspectRatio: AspectRatio = .original,
        goonerMode: Bool = false
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        
        // Berechne exakten Zeitpunkt basierend auf dem Prozentsatz
        let clampedPercent = min(max(timePercent, 0.0), 0.99)
        let targetTime = CMTimeMultiplyByFloat64(duration, multiplier: clampedPercent)
        
        let generator = AVAssetImageGenerator(asset: asset)
        
        // Konfiguriere den Generator für exakte Frame-Entnahme
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // WICHTIG: Erhalte die Rotation des Originalvideos (besonders für iPhone-Videos)
        generator.appliesPreferredTrackTransform = true
        
        print("[PastPhoto] 🔍 Extrahiere Frame bei \(String(format: "%.2f", CMTimeGetSeconds(targetTime)))s ...")
        
        // Moderne iOS 16+ API zur Frame-Extraktion
        var (cgImage, actualTime) = try await generator.image(at: targetTime)
        print("[PastPhoto] 🖼️ Frame extrahiert bei tatsächlicher Zeit: \(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s")
        
        // Apply aspect ratio crop
        if aspectRatio != .original {
            let imgSize = CGSize(width: cgImage.width, height: cgImage.height)
            let crop = cropRect(for: imgSize, ratio: aspectRatio)
            if let cropped = cgImage.cropping(to: crop) {
                cgImage = cropped
                print("[PastPhoto] 📐 Key Photo gecroppt: \(cropped.width)×\(cropped.height)")
            }
        }
        
        // Apply gooner effects
        if goonerMode {
            if let friedImage = GoonerEffects.deepFryCGImage(cgImage, stretch: true) {
                cgImage = friedImage
                print("[PastPhoto] 🐸 Gooner-Effekte auf Key Photo angewendet")
            }
        }
        
        // HEIC via CGImageDestination schreiben mit Apple MakerNote Metadata
        // HEIC ist zwingend nötig, da JPEG via CoreGraphics oft das MakerNote verwirft.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastphoto_key_\(UUID().uuidString).heic")
        
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw PastPhotoError.frameExtractionFailed
        }
        
        // Apple MakerNote mit Key 17 = assetIdentifier
        let makerNote: [String: Any] = ["17": assetIdentifier]
        let metadata: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: makerNote
        ]
        
        // Gooner mode: extremely low quality for compression artifacts
        let imageProperties: [String: Any] = goonerMode
            ? [kCGImageDestinationLossyCompressionQuality as String: 0.05]
            : [:]
        
        let combinedProps = metadata.merging(imageProperties) { _, new in new }
        
        CGImageDestinationAddImage(destination, cgImage, combinedProps as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PastPhotoError.frameExtractionFailed
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("[PastPhoto] ✅ HEIC erfolgreich gespeichert. Dateigröße: \(fileSize / 1024) KB")
        
        return outputURL
    }
}
