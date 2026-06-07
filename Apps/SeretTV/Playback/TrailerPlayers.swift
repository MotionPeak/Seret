import AVKit
import SwiftUI

/// Inline, muted, looping trailer for the detail backdrop (tvOS). Always muted — the focusable
/// Trailer button plays full-screen with sound; there is no inline unmute control (focus model).
struct InlineMutedTrailer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.play()
        v.player = player
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspectFill }
        }
    }
}

/// Full-screen trailer with native tvOS playback controls + sound. The Menu/back button exits.
struct FullScreenTrailer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.isMuted = false
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
        .onExitCommand { dismiss() }
    }
}
