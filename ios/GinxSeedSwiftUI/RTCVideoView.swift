import SwiftUI
import WebRTC

struct RTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirror: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity

        if context.coordinator.currentTrack === track {
            return
        }

        context.coordinator.currentTrack?.remove(uiView)
        track?.add(uiView)
        context.coordinator.currentTrack = track
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }

    final class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}
