import AVKit
import SwiftUI

/// Inline, muted-by-default, looping trailer for the hero backdrop: an `AVPlayerLayer` fills the
/// space (aspect-fill), no controls. `muted` is a binding so the capsule can flip it without
/// tearing the player down.
struct InlineTrailer: NSViewRepresentable {
    let url: URL
    @Binding var muted: Bool

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        player.play()
        view.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player?.isMuted = muted
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    /// NSView whose backing layer IS an `AVPlayerLayer` (fills bounds, aspect-fill).
    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
            playerLayer.videoGravity = .resizeAspectFill
            // Aspect-fill draws the video larger than the view; without a mask it spilled out of
            // the hero onto the page below (owner's screenshot). SwiftUI's `.clipped()` does not
            // reach an AppKit view's layer, so the layer clips itself.
            playerLayer.masksToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
    }
}
