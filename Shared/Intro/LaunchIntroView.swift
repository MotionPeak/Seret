import AVFoundation
import SwiftUI

/// The launch intro, shared by every app: the "Range" landscape of the Top Shelf, drawn in from the
/// dark — ridgelines pour in from the horizon, the triangle's peaks rise, the name arrives in the
/// sky, then the camera dives into the triangle and everything sinks into the app's navy.
///
/// It is a video, not live drawing: `Scripts/topshelf/render-intro.sh` renders it from the same
/// `art.js` that draws the Top Shelf, one file per screen shape, into each app's
/// `Resources/Intro/`. This view picks the file nearest its own shape and fills itself with it.
///
/// `released` lets a caller hold the intro on its last frame before the dive (`holdTime`) — the
/// Mac holds there until the library has answered, rather than diving into an empty shell.
/// `onHoldReached` fires once at that frame. Under Reduce Motion the hold frame shows as a still.
/// A missing or unplayable file never strands the app: the intro then finishes straight away.
struct LaunchIntroView: View {
    var released: Bool = true
    var onHoldReached: () -> Void = {}
    var onFinished: () -> Void

    @State private var playback: LaunchIntroPlayback?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The navy the video starts and ends on (`BG` in art.js), so the frames around it never flash.
    static let background = Color(red: 10 / 255, green: 13 / 255, blue: 20 / 255)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Self.background
                if let player = playback?.player {
                    IntroPlayerSurface(player: player)
                }
            }
            .onAppear {
                guard playback == nil else { return }
                let size = geo.size
                let url = LaunchIntroPlayback.videoURL(aspect: size.height > 0 ? size.width / size.height : 16 / 9)
                let playback = LaunchIntroPlayback(url: url, still: reduceMotion,
                                                   onHoldReached: onHoldReached, onFinished: onFinished)
                self.playback = playback
                playback.start(released: released)
            }
        }
        .ignoresSafeArea()
        .onChange(of: released) { _, now in if now { playback?.release() } }
        .onDisappear { playback?.stop() }
        .accessibilityHidden(true)
    }
}

/// Drives one play of the intro: start → (optionally) hold before the dive → end.
@MainActor
final class LaunchIntroPlayback {
    /// The frame where everything is in and nothing has dived yet (`INTRO_HOLD` in art.js).
    static let holdTime: TimeInterval = 2.7
    /// The whole video (`INTRO` in art.js).
    static let duration: TimeInterval = 3.4
    /// How long the Reduce Motion still shows before it may finish.
    static let stillTime: TimeInterval = 1.0

    let player: AVPlayer?
    private let still: Bool
    private let onHoldReached: () -> Void
    private let onFinished: () -> Void
    private var released = true
    private var reachedHold = false
    private var finished = false
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var watchdog: Task<Void, Never>?

    /// The bundled video nearest `aspect` (width ÷ height). The TV and the Mac ship one landscape
    /// file; the iPhone/iPad app ships landscape, iPad-portrait and iPhone-portrait files.
    static func videoURL(aspect: CGFloat) -> URL? {
        let name: String
        #if os(iOS)
        name = aspect >= 1 ? "intro-wide" : aspect >= 0.6 ? "intro-tall-pad" : "intro-tall-phone"
        #else
        name = "intro-wide"
        #endif
        return Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    init(url: URL?, still: Bool, onHoldReached: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.still = still
        self.onHoldReached = onHoldReached
        self.onFinished = onFinished
        guard let url else { player = nil; return }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        #if !os(macOS)
        player.allowsExternalPlayback = false
        #endif
        self.player = player
    }

    func start(released: Bool) {
        self.released = released
        guard let player, let item = player.currentItem else {
            // Nothing to play: behave as if the intro had run, so launch carries on.
            reachHold(); finishIfReleased(); return
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bailOut() }
        }
        if still {
            player.seek(to: CMTime(seconds: Self.holdTime, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            arm(after: Self.stillTime) { $0.reachHold(); $0.finishIfReleased() }
            return
        }
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: Self.holdTime, preferredTimescale: 600))],
            queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.reachHold() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        player.play()
        // A stalled decode must not hold launch: past the hold time (with margin), act as if the
        // hold frame was reached.
        arm(after: Self.holdTime + 1.5) { $0.reachHold() }
    }

    /// Lets a held intro dive and finish.
    func release() {
        guard !released else { return }
        released = true
        guard reachedHold, !finished else { return }
        if still || player == nil { finishIfReleased(); return }
        player?.play()
        arm(after: Self.duration - Self.holdTime + 1.0) { $0.finish() }
    }

    func stop() {
        watchdog?.cancel()
        player?.pause()
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
        for observer in [endObserver, failObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil; failObserver = nil
    }

    private func reachHold() {
        guard !reachedHold else { return }
        reachedHold = true
        onHoldReached()
        if !released { player?.pause() }
        else if !still, player != nil {
            arm(after: Self.duration - Self.holdTime + 1.0) { $0.finish() }
        }
    }

    private func finishIfReleased() { if released { finish() } }

    /// The file would not play: skip straight to the end, still honouring a hold.
    private func bailOut() {
        player?.pause()
        reachHold()
        finishIfReleased()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        stop()
        onFinished()
    }

    private func arm(after seconds: TimeInterval, _ action: @escaping (LaunchIntroPlayback) -> Void) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }
}

#if canImport(UIKit)
import UIKit

/// The intro's video layer, filling its frame.
private struct IntroPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}
}
#else
import AppKit

/// The intro's video layer, filling its frame.
private struct IntroPlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func makeBackingLayer() -> CALayer { playerLayer }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: LayerView, context: Context) {}
}
#endif
