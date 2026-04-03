import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = LucyRealtimeViewModel()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.11),
                        Color(red: 0.11, green: 0.15, blue: 0.21),
                        Color(red: 0.56, green: 0.26, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        heroPanel
                        setupPanel
                        controlsPanel
                        referencePanel
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ginx Seed")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.checkBackend()
                if AppConfiguration.autoConnectOnLaunch && !viewModel.isConnected {
                    await viewModel.connect()
                }
            }
            .onDisappear {
                Task {
                    await viewModel.disconnect()
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            viewModel.applyReferenceImage(image)
                        }
                    }
                }
            }
            .alert("Connection Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.lastError = nil
                }
            } message: {
                Text(viewModel.lastError ?? "Unknown error")
            }
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lucy realtime on iPhone")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Use the front camera, upload a reference image, and push prompt changes into a live Lucy 2 session.")
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 12) {
                statusBadge(title: viewModel.statusText)
                statusBadge(title: viewModel.generationSecondsText)
            }

            Text(viewModel.detailText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .aspectRatio(9 / 16, contentMode: .fit)

                if let remoteTrack = viewModel.remoteVideoTrack {
                    RTCVideoView(track: remoteTrack)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .aspectRatio(9 / 16, contentMode: .fit)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 42))
                        Text(viewModel.isStarting ? "Connecting to Lucy..." : "Waiting for transformed video")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(9 / 16, contentMode: .fit)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Camera")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))

                    RTCVideoView(track: viewModel.localVideoTrack, mirror: true)
                        .frame(width: 112, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                }
                .padding(16)
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iPhone Setup")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Backend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text(viewModel.backendURLText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

            Text("Run the Node token server on your computer, then point `GINXBackendBaseURL` at your computer's LAN IP before installing on a physical iPhone.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            Button {
                Task { await viewModel.checkBackend() }
            } label: {
                Text(viewModel.isCheckingBackend ? "Checking Backend..." : "Check Backend")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .disabled(viewModel.isCheckingBackend)
        }
        .padding(20)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Prompt")
                .font(.headline)
                .foregroundStyle(.white)

            TextField("", text: $viewModel.promptText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .lineLimit(3...6)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.updatePrompt() }
                } label: {
                    Text(viewModel.isUpdatingPrompt ? "Updating..." : "Apply Prompt")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(!viewModel.canApplyPrompt || viewModel.isBusy)

                Button {
                    Task { await viewModel.switchCamera() }
                } label: {
                    Label("Flip", systemImage: "camera.rotate")
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .disabled(viewModel.isBusy)
            }

            Button {
                Task {
                    if viewModel.isConnected {
                        await viewModel.disconnect()
                    } else {
                        await viewModel.connect()
                    }
                }
            } label: {
                Text(viewModel.isConnected ? "End Session" : "Start Session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryCapsuleButtonStyle())
            .disabled(viewModel.isBusy)
        }
        .padding(20)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reference Image")
                .font(.headline)
                .foregroundStyle(.white)

            if let image = viewModel.referencePreview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.system(size: 34))
                            Text("Choose a character image for Lucy 2")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Choose Reference")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
        }
        .padding(20)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func statusBadge(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            .foregroundStyle(.white)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { shouldShow in
                if !shouldShow {
                    viewModel.lastError = nil
                }
            }
        )
    }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.63, blue: 0.24),
                        Color(red: 0.96, green: 0.35, blue: 0.18)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.1))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
}
