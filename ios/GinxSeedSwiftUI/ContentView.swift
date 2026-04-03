import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("seed.hasSeenOnboarding") private var hasSeenOnboarding = false

    @StateObject private var viewModel = LucyRealtimeViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingSettings = false
    @State private var settingsDraft = SeedSettingsDraft()

    var body: some View {
        NavigationStack {
            ZStack {
                SeedBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroPanel
                        setupPanel
                        controlsPanel
                        referencePanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle("SEED")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        settingsDraft = SeedSettingsDraft()
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.white)
                    }
                }
            }
            .task {
                viewModel.reloadConfiguration()
                await viewModel.checkBackend()
                if hasSeenOnboarding && AppConfiguration.autoConnectOnLaunch && !viewModel.isConnected {
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
            .sheet(isPresented: $isShowingSettings) {
                SeedSettingsView(
                    draft: $settingsDraft,
                    onSave: {
                        AppConfiguration.saveSettings(
                            backendBaseURL: settingsDraft.backendBaseURL,
                            defaultPrompt: settingsDraft.defaultPrompt,
                            autoConnectOnLaunch: settingsDraft.autoConnectOnLaunch
                        )
                        viewModel.reloadConfiguration()
                        isShowingSettings = false

                        Task {
                            await viewModel.checkBackend()
                        }
                    },
                    onReset: {
                        AppConfiguration.resetSettings()
                        settingsDraft = SeedSettingsDraft()
                        viewModel.reloadConfiguration()

                        Task {
                            await viewModel.checkBackend()
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: onboardingBinding) {
                SeedOnboardingView(
                    backendURL: viewModel.backendURLText,
                    onOpenSettings: {
                        hasSeenOnboarding = true
                        settingsDraft = SeedSettingsDraft()
                        isShowingSettings = true
                    },
                    onContinue: {
                        hasSeenOnboarding = true
                    }
                )
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
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SEED for iPhone")
                            .font(.caption.weight(.semibold))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.7))

                        Text("Realtime character transformation, built like a native camera app.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(viewModel.detailText)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    Spacer(minLength: 12)

                    SeedMark()
                }

                HStack(spacing: 10) {
                    statusBadge(
                        title: viewModel.statusText,
                        tint: Color(red: 0.97, green: 0.48, blue: 0.25)
                    )
                    statusBadge(
                        title: viewModel.generationSecondsText,
                        tint: Color(red: 0.98, green: 0.74, blue: 0.31)
                    )
                    statusBadge(
                        title: viewModel.isConnected ? "Session Live" : "Standby",
                        tint: Color(red: 0.34, green: 0.79, blue: 0.63)
                    )
                }

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .aspectRatio(9 / 16, contentMode: .fit)

                    if let remoteTrack = viewModel.remoteVideoTrack {
                        RTCVideoView(track: remoteTrack)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .aspectRatio(9 / 16, contentMode: .fit)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 40))
                            Text(viewModel.isStarting ? "Building session..." : "Realtime preview appears here")
                                .font(.headline)
                            Text("Connect, point the camera, and SEED will stream the transformed result.")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(9 / 16, contentMode: .fit)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("INPUT")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.75))

                        RTCVideoView(track: viewModel.localVideoTrack, mirror: true)
                            .frame(width: 118, height: 168)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .padding(16)
                }
            }
        }
    }

    private var setupPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ready The Pipeline")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)

                        Text("SEED now includes in-app onboarding and settings, so your backend setup no longer depends on editing plist values by hand.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }

                    Spacer()

                    Button("Settings") {
                        settingsDraft = SeedSettingsDraft()
                        isShowingSettings = true
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend Endpoint")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))

                    Text(viewModel.backendURLText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }

                HStack(alignment: .top, spacing: 12) {
                    SetupStepCard(index: "01", title: "Run Server", detail: "Start the Node token server on your computer.")
                    SetupStepCard(index: "02", title: "Set LAN URL", detail: "Use Settings to swap localhost for your LAN IP.")
                    SetupStepCard(index: "03", title: "Use iPhone", detail: "Realtime camera capture still needs a physical device.")
                }

                Button {
                    Task { await viewModel.checkBackend() }
                } label: {
                    HStack {
                        Image(systemName: "bolt.horizontal.circle.fill")
                        Text(viewModel.isCheckingBackend ? "Checking Backend..." : "Check Backend Reachability")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCapsuleButtonStyle())
                .disabled(viewModel.isCheckingBackend)
            }
        }
    }

    private var controlsPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Direction")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Prompt changes apply to the active Lucy session in realtime.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.75))
                    }

                    Spacer()
                }

                TextField("", text: $viewModel.promptText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .lineLimit(4...7)

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.updatePrompt() }
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text(viewModel.isUpdatingPrompt ? "Updating..." : "Apply Prompt")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(!viewModel.canApplyPrompt || viewModel.isBusy)

                    Button {
                        Task { await viewModel.switchCamera() }
                    } label: {
                        Label("Flip", systemImage: "camera.rotate.fill")
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
                    HStack {
                        Image(systemName: viewModel.isConnected ? "stop.circle.fill" : "play.circle.fill")
                        Text(viewModel.isConnected ? "End Session" : "Start Session")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionButtonStyle(isConnected: viewModel.isConnected))
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var referencePanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Reference Character")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Drop in a face, costume, or styled portrait to anchor the transformation.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))

                if let image = viewModel.referencePreview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 240)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.rectangle.stack.fill")
                                    .font(.system(size: 34))
                                Text("Choose a reference image")
                                    .font(.headline)
                                Text("Character likeness and styling cues will be sent with your prompt.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.68))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 22)
                            }
                            .foregroundStyle(Color.white.opacity(0.84))
                        }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Choose Reference")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
            }
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .foregroundStyle(.white)
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding },
            set: { shouldShow in
                hasSeenOnboarding = !shouldShow
            }
        )
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

private struct SeedSettingsDraft {
    var backendBaseURL = AppConfiguration.backendBaseURL.absoluteString
    var defaultPrompt = AppConfiguration.defaultPrompt
    var autoConnectOnLaunch = AppConfiguration.autoConnectOnLaunch
}

private struct SeedOnboardingView: View {
    let backendURL: String
    let onOpenSettings: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            SeedBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                SeedMark()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Welcome to SEED")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("This app is ready to build in the cloud right now. When you eventually test on a real iPhone, SEED will connect to your token server and stream the Lucy transformation live.")
                        .font(.title3)
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                VStack(spacing: 14) {
                    OnboardingRow(
                        title: "Backend first",
                        detail: "Current endpoint: \(backendURL)"
                    )
                    OnboardingRow(
                        title: "Physical device later",
                        detail: "GitHub validates the native build today, but the live camera flow still needs iPhone hardware."
                    )
                    OnboardingRow(
                        title: "Settings are in-app",
                        detail: "You can change backend URL, prompt defaults, and auto-connect behavior without editing plist files."
                    )
                }

                Spacer()

                VStack(spacing: 12) {
                    Button("Open Settings") {
                        onOpenSettings()
                    }
                    .buttonStyle(PrimaryCapsuleButtonStyle())

                    Button("Continue to App") {
                        onContinue()
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                }
            }
            .padding(24)
        }
    }
}

private struct SeedSettingsView: View {
    @Binding var draft: SeedSettingsDraft
    let onSave: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SeedBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Connection")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)

                                settingsField(
                                    title: "Backend URL",
                                    text: $draft.backendBaseURL,
                                    prompt: "http://192.168.1.25:8787"
                                )

                                Toggle(isOn: $draft.autoConnectOnLaunch) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto-connect on launch")
                                            .foregroundStyle(.white)
                                        Text("Only turn this on when your backend is reliably reachable.")
                                            .font(.footnote)
                                            .foregroundStyle(Color.white.opacity(0.7))
                                    }
                                }
                                .tint(Color(red: 0.97, green: 0.48, blue: 0.25))
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Creative Default")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)

                                settingsField(
                                    title: "Default prompt",
                                    text: $draft.defaultPrompt,
                                    prompt: "Transform into this character with polished cinematic detail",
                                    axis: .vertical
                                )
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Actions")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)

                                Button("Save Settings") {
                                    onSave()
                                }
                                .buttonStyle(PrimaryCapsuleButtonStyle())

                                Button("Reset to Bundle Defaults") {
                                    onReset()
                                }
                                .buttonStyle(SecondaryCapsuleButtonStyle())
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func settingsField(
        title: String,
        text: Binding<String>,
        prompt: String,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            TextField(prompt, text: text, axis: axis)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .lineLimit(axis == .vertical ? 4...7 : 1...1)
        }
    }
}

private struct OnboardingRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 0.98, green: 0.72, blue: 0.28))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SeedBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.19, green: 0.09, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.94, green: 0.46, blue: 0.22).opacity(0.32))
                .frame(width: 280)
                .blur(radius: 60)
                .offset(x: 120, y: -260)

            Circle()
                .fill(Color(red: 0.97, green: 0.76, blue: 0.33).opacity(0.18))
                .frame(width: 300)
                .blur(radius: 70)
                .offset(x: -130, y: 180)
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct SeedMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.72, blue: 0.28),
                            Color(red: 0.94, green: 0.39, blue: 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)

            Text("S")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.08, blue: 0.06))
        }
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 8)
    }
}

private struct SetupStepCard: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(index)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.28))

            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        Color(red: 1.0, green: 0.73, blue: 0.30),
                        Color(red: 0.96, green: 0.39, blue: 0.20)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(Color(red: 0.12, green: 0.08, blue: 0.06))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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

private struct SessionButtonStyle: ButtonStyle {
    let isConnected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(isConnected ? Color.white.opacity(0.08) : Color.white)
            .foregroundStyle(isConnected ? .white : Color.black)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isConnected ? Color.white.opacity(0.14) : Color.clear,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

#Preview {
    ContentView()
}
