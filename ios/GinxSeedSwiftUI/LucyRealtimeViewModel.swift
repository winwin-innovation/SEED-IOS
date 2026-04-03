import DecartSDK
import Foundation
import SwiftUI
import UIKit
import WebRTC

@MainActor
final class LucyRealtimeViewModel: ObservableObject {
    @Published var promptText: String
    @Published var statusText = "Idle"
    @Published var detailText = "Configure the backend URL, then connect on a physical iPhone."
    @Published var isConnected = false
    @Published var isStarting = false
    @Published var isUpdatingPrompt = false
    @Published var isCheckingBackend = false
    @Published var lastError: String?
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var referencePreview: UIImage?
    @Published var generationSecondsText = "0.0s"

    private let tokenService = TokenService()
    private let model = Models.realtime(.lucy_2_rt)

    private var manager: DecartRealtimeManager?
    #if !targetEnvironment(simulator)
    private var capture: RealtimeCapture?
    #endif
    private var stateTask: Task<Void, Never>?
    private var remoteStreamTask: Task<Void, Never>?
    private var referenceImageData: Data?

    init() {
        promptText = AppConfiguration.defaultPrompt
    }

    var backendURLText: String {
        tokenService.backendSummary()
    }

    var canApplyPrompt: Bool {
        !isUpdatingPrompt && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBusy: Bool {
        isStarting || isUpdatingPrompt || isCheckingBackend
    }

    func reloadConfiguration() {
        if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isConnected {
            promptText = AppConfiguration.defaultPrompt
        }
    }

    func connect() async {
        guard !isStarting, manager == nil else { return }

        #if targetEnvironment(simulator)
        lastError = "The iOS Simulator cannot use Decart camera capture. Use GitHub Actions for compile checks and a physical iPhone for realtime testing."
        statusText = "Simulator Only"
        detailText = "This build target is valid for CI, but Lucy realtime needs a real iPhone camera."
        isConnected = false
        isStarting = false
        return
        #else
        isStarting = true
        lastError = nil
        statusText = "Connecting"
        detailText = "Checking backend and requesting a short-lived client token."

        do {
            try await tokenService.checkBackendHealth()
            let clientToken = try await tokenService.fetchRealtimeToken()
            let config = DecartConfiguration(apiKey: clientToken)
            let client = DecartClient(decartConfiguration: config)

            let manager = try client.createRealtimeManager(
                options: RealtimeConfiguration(
                    model: model,
                    initialPrompt: makePrompt()
                )
            )

            let videoSource = manager.createVideoSource()
            let videoTrack = manager.createVideoTrack(
                source: videoSource,
                trackId: "camera-video"
            )

            let capture = RealtimeCapture(
                model: model,
                videoSource: videoSource,
                orientation: .portrait,
                initialPosition: .front
            )

            try await capture.startCapture()

            let localStream = RealtimeMediaStream(videoTrack: videoTrack, id: .localStream)
            let remoteStream = try await manager.connect(localStream: localStream)

            self.manager = manager
            self.capture = capture
            self.localVideoTrack = videoTrack
            self.remoteVideoTrack = remoteStream.videoTrack

            observeStateChanges(from: manager)
            observeRemoteStreamChanges(from: manager)

            isConnected = true
            statusText = "Live"
            detailText = "Lucy realtime session is active."
        } catch {
            lastError = error.localizedDescription
            statusText = "Error"
            detailText = "The app could not start the realtime session."
            await disconnect()
        }

        isStarting = false
        #endif
    }

    func applyReferenceImage(_ image: UIImage?) {
        referencePreview = image
        referenceImageData = image?.jpegData(compressionQuality: 0.85)
    }

    func updatePrompt() async {
        guard canApplyPrompt else { return }

        guard let manager else {
            await connect()
            if self.manager == nil {
                return
            }
            await updatePrompt()
            return
        }

        isUpdatingPrompt = true
        lastError = nil
        manager.setPrompt(makePrompt())
        detailText = "Prompt sent to the live Lucy session."
        isUpdatingPrompt = false
    }

    func checkBackend() async {
        guard !isCheckingBackend else { return }

        isCheckingBackend = true
        lastError = nil

        do {
            try await tokenService.checkBackendHealth()
            statusText = isConnected ? statusText : "Backend Ready"
            detailText = "The token server responded successfully."
        } catch {
            lastError = error.localizedDescription
            statusText = "Backend Offline"
            detailText = "The iPhone cannot currently reach the token server."
        }

        isCheckingBackend = false
    }

    func switchCamera() async {
        #if targetEnvironment(simulator)
        lastError = "Camera switching is unavailable in the iOS Simulator."
        #else
        do {
            try await capture?.switchCamera()
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    func disconnect() async {
        stateTask?.cancel()
        remoteStreamTask?.cancel()
        stateTask = nil
        remoteStreamTask = nil

        await manager?.disconnect()
        #if !targetEnvironment(simulator)
        await capture?.stopCapture()
        #endif

        manager = nil
        #if !targetEnvironment(simulator)
        capture = nil
        #endif
        localVideoTrack = nil
        remoteVideoTrack = nil
        isConnected = false
        isStarting = false
        isUpdatingPrompt = false
        isCheckingBackend = false
        generationSecondsText = "0.0s"

        if statusText != "Error" {
            statusText = "Disconnected"
            detailText = "Reconnect when the backend server is reachable from your device."
        }
    }

    private func observeStateChanges(from manager: DecartRealtimeManager) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            guard let self else { return }

            for await state in manager.events {
                await MainActor.run {
                    if let tick = state.generationTick {
                        self.generationSecondsText = String(format: "%.1fs", tick)
                    }

                    switch state.connectionState {
                    case .connecting:
                        self.statusText = "Connecting"
                        self.detailText = "Negotiating the WebRTC session."
                    case .connected:
                        self.statusText = "Connected"
                        self.detailText = "Camera feed is connected. Waiting for generation."
                        self.isConnected = true
                    case .generating:
                        self.statusText = "Generating"
                        self.detailText = "Lucy is rendering the transformed stream."
                        self.isConnected = true
                    case .reconnecting:
                        self.statusText = "Reconnecting"
                        self.detailText = "Attempting to recover the realtime session."
                        self.isConnected = false
                    case .disconnected:
                        self.statusText = "Disconnected"
                        self.detailText = "The realtime session ended."
                        self.isConnected = false
                    case .error:
                        self.statusText = "Error"
                        self.detailText = "The realtime manager reported an error."
                        self.isConnected = false
                    case .idle:
                        break
                    }
                }
            }
        }
    }

    private func observeRemoteStreamChanges(from manager: DecartRealtimeManager) {
        remoteStreamTask?.cancel()
        remoteStreamTask = Task { [weak self] in
            guard let self else { return }

            for await stream in manager.remoteStreamUpdates {
                await MainActor.run {
                    self.remoteVideoTrack = stream.videoTrack
                }
            }
        }
    }

    private func makePrompt() -> DecartPrompt {
        DecartPrompt(
            text: promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppConfiguration.defaultPrompt
                : promptText,
            referenceImageData: referenceImageData,
            enrich: true
        )
    }
}
