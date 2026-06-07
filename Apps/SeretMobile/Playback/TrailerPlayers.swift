import AVKit
import SwiftUI

/// Inline, muted-by-default, looping trailer for the detail backdrop. No controls; an `AVPlayerLayer`
/// fills the space (aspect-fill). `muted` is a binding so a parent unmute button can flip it.
struct InlineMutedTrailer: UIViewRepresentable {
    let url: URL
    @Binding var muted: Bool

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        player.play()
        v.player = player
        return v
    }

    func updateUIView(_ v: PlayerLayerView, context: Context) {
        v.playerLayer.player?.isMuted = muted
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    /// UIView whose backing layer is an AVPlayerLayer (fills bounds, aspect-fill).
    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspectFill }
        }
    }
}

/// Full-screen trailer with native controls + sound. Presented as a full-screen cover.
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
        .overlay(alignment: .topLeading) {
            Button("Done") { dismiss() }
                .padding().tint(Theme.Palette.gold)
        }
        .onAppear {
            let p = AVPlayer(url: url)
            p.isMuted = false
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
        .preferredColorScheme(.dark)
    }
}
