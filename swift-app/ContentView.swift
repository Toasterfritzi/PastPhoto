import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = PastPhotoViewModel()
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Video Picker Section ──
                    videoSection

                    // ── Trim & Frame Controls (visible after video loaded) ──
                    if viewModel.videoDuration != nil {
                        trimSection
                            .transition(.blurReplace.combined(with: .opacity))
                    }
                    
                    // ── Speed & Aspect Ratio ──
                    if viewModel.videoDuration != nil {
                        playbackSection
                            .transition(.blurReplace.combined(with: .opacity))
                    }

                    // ── Toggle Controls ──
                    toggleSection

                    // ── Convert Button ──
                    convertButton

                    // ── Progress / Result (morphing) ──
                    if viewModel.isProcessing {
                        progressSection
                    }

                    if viewModel.isComplete {
                        resultSection
                    }

                    // ── Error ──
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
                .animation(.spring(duration: 0.5), value: viewModel.videoDuration != nil)
                .animation(.spring(duration: 0.5), value: viewModel.isProcessing)
                .animation(.spring(duration: 0.5), value: viewModel.isComplete)
            }
            .navigationTitle("PastPhoto")
        }
    }

    // MARK: - Video Section

    private var videoSection: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {

                // Selected video indicator
                if let selectedVideoName = viewModel.selectedVideoName {
                    HStack(spacing: 10) {
                        Image(systemName: "film.fill")
                            .foregroundStyle(.tint)
                            .font(.body)
                        Text(selectedVideoName)
                            .lineLimit(1)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button {
                            withAnimation { viewModel.clearSelection() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }

                // Photo Picker
                PhotosPicker(
                    selection: $viewModel.selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Aus Fotos wählen", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glass)
            }
            .padding()
        }
    }

    // MARK: - Trim & Frame Section

    private var trimSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "scissors")
                    .foregroundStyle(.orange)
                Text("Zuschnitt & Key Frame")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            
            if let duration = viewModel.videoDuration {
                // Trim Start
                GlassSlider(
                    value: $viewModel.trimStart,
                    range: 0...max(duration - 0.1, 0.1),
                    label: "Start",
                    icon: "arrow.right.to.line",
                    unit: "s",
                    tintColor: .orange
                )
                .onChange(of: viewModel.trimStart) {
                    // Ensure trimEnd stays after trimStart
                    if viewModel.trimEnd <= viewModel.trimStart {
                        viewModel.trimEnd = min(viewModel.trimStart + 0.5, duration)
                    }
                }

                // Trim End
                let maxEnd = viewModel.experimentalMode ? duration : min(duration, viewModel.trimStart + 2.5)
                GlassSlider(
                    value: $viewModel.trimEnd,
                    range: (viewModel.trimStart + 0.1)...max(maxEnd, viewModel.trimStart + 0.2),
                    label: "Ende",
                    icon: "arrow.left.to.line",
                    unit: "s",
                    tintColor: .orange
                )

                // Key Frame
                GlassSlider(
                    value: $viewModel.keyFramePercent,
                    range: 0...0.99,
                    label: "Key Frame",
                    icon: "photo.fill",
                    unit: "%",
                    tintColor: .blue,
                    decimals: 0
                )
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Speed picker
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(.purple)
                Text("Geschwindigkeit")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            
            GlassSegmentedPicker(
                selection: $viewModel.playbackSpeed,
                options: PlaybackSpeed.allCases,
                label: { $0.label }
            )

            // Aspect ratio picker
            HStack {
                Image(systemName: "aspectratio")
                    .foregroundStyle(.cyan)
                Text("Seitenverhältnis")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.top, 4)
            
            GlassSegmentedPicker(
                selection: $viewModel.aspectRatio,
                options: AspectRatio.allCases,
                label: { $0.rawValue }
            )
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Toggle Section

    private var toggleSection: some View {
        VStack(spacing: 14) {
            // Experimental mode
            Toggle(isOn: $viewModel.experimentalMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Experimenteller Modus", systemImage: "flask.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Erlaubt Videos länger als 2,5 Sekunden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: viewModel.experimentalMode) {
                // Update trim end when toggling experimental mode
                if let dur = viewModel.videoDuration {
                    if viewModel.experimentalMode {
                        viewModel.trimEnd = dur
                    } else {
                        viewModel.trimEnd = min(viewModel.trimEnd, viewModel.trimStart + 2.5)
                    }
                }
            }

            Divider().opacity(0.3)

            // Bounce mode
            Toggle(isOn: $viewModel.bounceMode) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Bounce Loop", systemImage: "arrow.trianglehead.2.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                    Text("Live Photo spielt vorwärts-rückwärts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.3)

            // Gooner mode 🐸
            Toggle(isOn: $viewModel.goonerMode) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Label("Gooner-Modus", systemImage: "flame.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(viewModel.goonerMode ? .red : .primary)
                        
                        if viewModel.goonerMode {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: viewModel.goonerMode)
                        }
                    }
                    Text("Extremes Deep-Fry: Bild verzerrt, Video frittiert 🐸")
                        .font(.caption)
                        .foregroundStyle(viewModel.goonerMode ? .red.opacity(0.8) : .secondary)
                }
            }
            .tint(.red)
            
            // Gooner warning
            if viewModel.goonerMode {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.red)
                    Text("Audio wird ebenfalls verzerrt!")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .glassEffect(.clear, in: .rect(cornerRadius: 10))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .animation(.spring(duration: 0.3), value: viewModel.goonerMode)
    }

    // MARK: - Convert Button

    private var convertButton: some View {
        Button {
            Task { await viewModel.convertAndSave() }
        } label: {
            Label(
                viewModel.goonerMode ? "Frittieren & Speichern 🐸" : "Konvertieren & Speichern",
                systemImage: viewModel.goonerMode ? "flame.fill" : "livephoto"
            )
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .disabled(!viewModel.canConvert)
        .tint(viewModel.goonerMode ? .red : (viewModel.canConvert ? .green : .gray))
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(viewModel.statusMessage)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(.clear, in: .rect(cornerRadius: 20))
        .glassEffectID("statusCard", in: glassNamespace)
        .transition(.blurReplace.combined(with: .opacity))
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.goonerMode ? "flame.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(viewModel.goonerMode ? .red : .green)
                .symbolEffect(.bounce, value: viewModel.isComplete)

            Text(viewModel.goonerMode ? "Frittiert & Gespeichert! 🐸" : "Live Photo gespeichert!")
                .font(.title2.weight(.bold))

            Text("Öffne die Fotos-App und halte das Bild gedrückt, um die Animation zu sehen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Action buttons
            HStack(spacing: 12) {
                // Wallpaper button
                Button {
                    viewModel.shareForWallpaper()
                } label: {
                    Label("In Fotos öffnen", systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                .tint(.blue)
                
                // New video button
                Button {
                    withAnimation(.spring(duration: 0.5)) { viewModel.reset() }
                } label: {
                    Label("Neues Video", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .glassEffectID("statusCard", in: glassNamespace)
        .transition(.blurReplace.combined(with: .opacity))
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("Fehler aufgetreten")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Schließen") {
                withAnimation { viewModel.errorMessage = nil }
            }
            .buttonStyle(.glass)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
