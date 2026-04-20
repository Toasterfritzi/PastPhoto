import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = PastPhotoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // ── Video Picker Section ──
                    videoSection

                    // ── Progress ──
                    if viewModel.isProcessing {
                        progressSection
                    }

                    // ── Result ──
                    if viewModel.isComplete {
                        resultSection
                    }

                    // ── Error ──
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("PastPhoto")
        }
    }

    // MARK: - Video Section

    private var videoSection: some View {
        GlassEffectContainer {
            VStack(spacing: 20) {

                // Selected video indicator
                if let selectedVideoName = viewModel.selectedVideoName {
                    HStack {
                        Image(systemName: "film.fill")
                            .foregroundStyle(.tint)
                        Text(selectedVideoName)
                            .lineLimit(1)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button {
                            viewModel.clearSelection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
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

                // Experimental toggle
                Toggle(isOn: $viewModel.experimentalMode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Experimenteller Modus")
                            .font(.subheadline.weight(.semibold))
                        Text("Erlaubt Videos länger als 2,5 Sekunden")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Action Button
                Button {
                    Task { await viewModel.convertAndSave() }
                } label: {
                    Label("Konvertieren & Speichern", systemImage: "livephoto")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glass)
                .disabled(!viewModel.canConvert)
                .tint(viewModel.canConvert ? .green : .gray)
            }
            .padding()
        }
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
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: viewModel.isComplete)

            Text("Live Photo gespeichert!")
                .font(.title2.weight(.bold))

            Text("Öffne die Fotos-App und halte das Bild gedrückt, um die Animation zu sehen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Neues Video") {
                withAnimation { viewModel.reset() }
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .transition(.blurReplace.combined(with: .opacity))
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
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
