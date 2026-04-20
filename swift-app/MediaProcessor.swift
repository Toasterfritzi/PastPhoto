import Foundation
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Handles all local AVFoundation video processing (trimming, exporting, frame extraction).
enum MediaProcessor {
    
    /// Exportiert das Video als QuickTime MOV mit eingebettetem Content Identifier.
    /// Nutzt AVAssetWriter statt AVAssetExportSession, damit die Live-Photo-Metadaten
    /// (Content Identifier + Still Image Time) korrekt in die Datei geschrieben werden.
    static func exportVideo(from sourceURL: URL, maxDuration: Double?, assetIdentifier: String) async throws -> URL {
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
        
        // Effektive Dauer bestimmen
        let effectiveDuration: Double
        if let maxDur = maxDuration, durationSeconds > maxDur {
            effectiveDuration = maxDur
            print("[PastPhoto] ✂️ Trimme Video auf max. \(maxDur) Sekunden")
        } else {
            effectiveDuration = durationSeconds
        }
        
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: effectiveDuration, preferredTimescale: 600)
        )
        
        // ── AVAssetReader einrichten ──
        let reader = try AVAssetReader(asset: asset)
        
        // Video Track lesen
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw PastPhotoError.exportFailed("Keine Video-Spur gefunden.")
        }
        
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        reader.timeRange = timeRange
        reader.add(videoReaderOutput)
        
        // Audio Track (optional)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderTrackOutput? = nil
        if let audioTrack = audioTracks.first {
            let aOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ])
            reader.add(aOutput)
            audioReaderOutput = aOutput
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
        
        // Video Track Einstellungen
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let isPortrait = transform.a == 0 && transform.d == 0
        let videoWidth = isPortrait ? abs(naturalSize.height) : abs(naturalSize.width)
        let videoHeight = isPortrait ? abs(naturalSize.width) : abs(naturalSize.height)
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoWriterInput.transform = transform
        videoWriterInput.expectsMediaDataInRealTime = false
        writer.add(videoWriterInput)
        
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
            let stillTime = CMTime(seconds: effectiveDuration / 2.0, preferredTimescale: 600)
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
        
        // ── Video und Audio Samples parallel kopieren ──
        // WICHTIG: AVAssetWriter puffert nur eine begrenzte Menge an Daten pro Track.
        // Wenn man erst das komplette Video und dann das komplette Audio schreibt,
        // blockiert AVAssetWriter bei langen Videos ("interleaving deadlock"), 
        // weil die Audio-Spur zu weit hinterherhinkt.
        // Daher MÜSSEN beide Tracks gleichzeitig (concurrently) verarbeitet werden!
        
        await withTaskGroup(of: Void.self) { group in
            // Video-Task
            group.addTask {
                nonisolated(unsafe) let safeVideoInput = videoWriterInput
                nonisolated(unsafe) let safeVideoOutput = videoReaderOutput
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    safeVideoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.write")) {
                        while safeVideoInput.isReadyForMoreMediaData {
                            guard let sampleBuffer = safeVideoOutput.copyNextSampleBuffer() else {
                                safeVideoInput.markAsFinished()
                                continuation.resume()
                                return
                            }
                            safeVideoInput.append(sampleBuffer)
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
    
    /// Extrahiert asynchron einen Frame aus dem Video und speichert ihn als HEIC.
    /// Fügt den `assetIdentifier` via CGImageDestination ein.
    static func generateKeyPhoto(from videoURL: URL, at timePercent: Double = 0.5, assetIdentifier: String) async throws -> URL {
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
        let (cgImage, actualTime) = try await generator.image(at: targetTime)
        print("[PastPhoto] 🖼️ Frame extrahiert bei tatsächlicher Zeit: \(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s")
        
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
        
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PastPhotoError.frameExtractionFailed
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        print("[PastPhoto] ✅ HEIC erfolgreich gespeichert. Dateigröße: \(fileSize / 1024) KB")
        
        return outputURL
    }
}
