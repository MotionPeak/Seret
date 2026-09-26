import AVKit
import SwiftUI

/// Inline, muted-by-default, looping trailer for the hero backdrop: the hero's still, then the video
/// fading in over it the moment it has a picture — aspect-fill, no controls. `muted` is a binding so
/// the capsule can flip it without tearing the player down.
///
/// The still is drawn HERE, in AppKit, not by SwiftUI underneath: on macOS 26 a SwiftUI `Image`
/// beneath an AppKit video view makes SwiftUI composite the video about half see-through — over the
/// still, and above the shading meant to sit on top of it (the owner saw the Watchlist grid through
/// a trailer). Measured: a colour or a gradient underneath composites correctly; any image does not.
struct InlineTrailer: NSViewRepresentable {
    let url: URL
    /// The hero's backdrop, shown until the video has a picture.
    let still: CGImage?
    @Binding var muted: Bool
    /// Called once the video has its first picture and starts fading in over the still.
    var onPicture: () -> Void = {}

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.still = still
        view.onPicture = onPicture
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
        view.still = still
        view.onPicture = onPicture
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    /// Hosts its own layer tree: the still at the bottom, the video over it. Both aspect-fill, so
    /// both draw larger than the view — the root layer clips them, since SwiftUI's `.clipped()` does
    /// not reach an AppKit layer (the video used to spill out of the hero onto the page below).
    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        private let stillLayer = CALayer()
        private var readiness: NSKeyValueObservation?
        var onPicture: () -> Void = {}

        var still: CGImage? {
            didSet { if still !== oldValue { stillLayer.contents = still } }
        }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            let root = CALayer()
            root.masksToBounds = true
            // The hero's scroll fade must fade the finished picture — without this it reached the
            // still and the video separately, and the still showed through the video mid-scroll.
            root.allowsGroupOpacity = true
            layer = root                    // set before `wantsLayer`: this view hosts the tree
            wantsLayer = true
            stillLayer.contentsGravity = .resizeAspectFill
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.opacity = 0         // until it has a picture — then `revealVideo`
            root.addSublayer(stillLayer)
            root.addSublayer(playerLayer)
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in self?.revealVideo() }
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // follow the view exactly, never animate there
            stillLayer.frame = bounds
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        private func revealVideo() {
            guard playerLayer.opacity == 0 else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.6
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            playerLayer.opacity = 1
            playerLayer.add(fade, forKey: "reveal")
            onPicture()
            // Once the video fully covers it, the still has nothing left to do.
            let covered = fade.duration + 0.1
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(covered))
                self?.stillLayer.isHidden = true
            }
        }
    }
}
