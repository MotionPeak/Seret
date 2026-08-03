import Foundation
#if canImport(MediaPlayer) && canImport(UIKit)
import MediaPlayer
import UIKit
import QuartzCore

/// `NowPlayingControlling` backed by MediaPlayer. Declaring these commands is what makes the
/// iPhone Remote app render a transport row with ±10s buttons and a scrubber — the same mechanism
/// YouTube uses. It also lights up Siri ("skip forward 30 seconds"), Control Center, HomePod
/// handoff and HDMI-CEC TV remotes, none of which any on-screen gesture can reach.
@MainActor
public final class NowPlayingCenter: NowPlayingControlling {
    private var handlers: NowPlayingHandlers?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?
    /// The resolved poster, held here rather than read back out of `MPNowPlayingInfoCenter`.
    private var artwork: MPMediaItemArtwork?
    /// The most recent state we were given, pushed or not — so a late-arriving poster can refresh
    /// the entry against current values.
    private var lastInfo: NowPlayingInfo?
    /// Suppresses the ~4/second no-op pushes. See `NowPlayingThrottle`.
    private var throttle = NowPlayingThrottle()
    /// The skip interval offered to the system, in seconds. Matches the on-screen ±10s.
    private let skipInterval: Double = 10

    public init() {}

    /// Install the system transport handlers.
    ///
    /// Every handler below is `@Sendable`, which makes it **non-isolated**, and defers the real
    /// work to a `@MainActor` hop. That shape is deliberate: Apple documents no thread on which
    /// `MPRemoteCommand` invokes these blocks, and a closure written inline in this `@MainActor`
    /// class would otherwise inherit main-actor isolation, so Swift would inject an isolation check
    /// that calls `dispatch_assert_queue(main)` and **traps** the moment MediaPlayer used any other
    /// queue. That is not hypothetical for this framework — it is exactly how the Now Playing
    /// artwork handler crashed the app on entering every title (see `artwork(for:)` below).
    /// An undocumented contract whose failure mode is SIGTRAP is not one to lean on.
    ///
    /// The cost is that a command reports `.success` before its effect runs. For transport actions
    /// that is unobservable; the alternative — reading main-actor state synchronously off the main
    /// actor — is the crash itself.
    public func activate(_ handlers: NowPlayingHandlers) {
        self.handlers = handlers
        let center = MPRemoteCommandCenter.shared()
        // Read on the main actor, captured as plain Sendable values, so the handlers never touch
        // actor state to decide what to return.
        let skip = skipInterval
        let hasNextTrack = handlers.nextTrack != nil

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.handlers?.play() }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.handlers?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.handlers?.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipForwardCommand.addTarget { @Sendable [weak self] event in
            // Pull the interval out here: the event object is not Sendable and must not cross.
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? skip
            Task { @MainActor in self?.handlers?.skip(interval) }
            return .success
        }
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.addTarget { @Sendable [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? skip
            Task { @MainActor in self?.handlers?.skip(-interval) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            Task { @MainActor in self?.handlers?.seek(position) }
            return .success
        }

        center.changePlaybackRateCommand.isEnabled = true
        center.changePlaybackRateCommand.supportedPlaybackRates = [1, 2, 3, 4].map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { @Sendable [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = Double(e.playbackRate)
            Task { @MainActor in self?.handlers?.setRate(rate) }
            return .success
        }

        // `.noSuchContent` has to be decided synchronously, so it reads the captured Bool rather
        // than reaching into `handlers` — that read is what would have needed the main actor.
        center.nextTrackCommand.isEnabled = hasNextTrack
        center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            guard hasNextTrack else { return .noSuchContent }
            Task { @MainActor in self?.handlers?.nextTrack?() }
            return .success
        }
    }

    /// Take the latest playback state, and write it to the system only if the system's own
    /// extrapolation would now be wrong.
    ///
    /// `PlayerModel.tick()` calls this on every VLCKit time event — several times a second — and
    /// every push makes MediaPlayer rebuild its dictionary and re-encode the poster JPEG
    /// (`-[MPMediaItemArtwork jpegDataWithSize:]`). The system derives the playhead from
    /// elapsed-time + rate on its own, so all those pushes told it what it already knew.
    public func update(_ info: NowPlayingInfo) {
        lastInfo = info
        loadArtworkIfNeeded(info.artworkURL)
        let identity = "\(info.title)|\(info.showName ?? "")|\(info.duration)"
        guard throttle.shouldPush(identity: identity, position: info.position,
                                  rate: info.rate, now: CACurrentMediaTime()) else { return }
        push(info)
    }

    /// Write the entry to the system.
    ///
    /// Note what this does NOT do: read `MPNowPlayingInfoCenter.default().nowPlayingInfo` back to
    /// recover the artwork. That getter is a synchronous cross-process call, and doing it on every
    /// tick was half the cost of this path. The poster is kept in `artwork` instead.
    private func push(_ info: NowPlayingInfo) {
        var entry: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position,
            MPNowPlayingInfoPropertyPlaybackRate: info.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let show = info.showName { entry[MPMediaItemPropertyArtist] = show }
        if let artwork { entry[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = entry
    }

    public func deactivate() {
        artworkTask?.cancel()
        artworkTask = nil
        lastArtworkURL = nil
        artwork = nil
        lastInfo = nil
        throttle.reset()          // the next session must refresh the entry unconditionally
        let center = MPRemoteCommandCenter.shared()
        let commands: [MPRemoteCommand] = [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.changePlaybackPositionCommand, center.changePlaybackRateCommand,
            center.nextTrackCommand,
        ]
        for command in commands {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        handlers = nil
    }

    /// Fetch the poster once per URL, then refresh the entry with it. This push bypasses the
    /// throttle: new artwork is exactly the kind of change the system cannot infer for itself.
    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != lastArtworkURL else { return }
        lastArtworkURL = url
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, let self,
                  let image = UIImage(data: data) else { return }
            self.artwork = Self.artwork(for: image)
            if let info = self.lastInfo { self.push(info) }
        }
    }

    /// Build the artwork OUTSIDE any actor isolation. MediaPlayer calls `requestHandler` on its own
    /// private queue to rasterise the poster (`-[MPMediaItemArtwork jpegDataWithSize:]`, reached
    /// from `_onQueue_pushNowPlayingInfoAndRetry:`). A closure formed inside this `@MainActor` class
    /// INHERITS main-actor isolation, so Swift injects an isolation check that calls
    /// `dispatch_assert_queue(main)` — which trips instantly on MediaPlayer's queue and kills the
    /// app with SIGTRAP in `_dispatch_assert_queue_fail`. It crashed on entering any title, the
    /// moment the poster finished downloading. Forming the closure in a `nonisolated` context keeps
    /// it isolation-free, so it can run wherever MediaPlayer likes.
    ///
    /// `nonisolated` is load-bearing, not stylistic. It is `internal` rather than `private` so
    /// `NowPlayingArtworkTests` can call it off the main actor — that suite is tvOS app-hosted
    /// because this file does not compile on macOS, so `swift test` can never reach it. Removing
    /// `nonisolated` breaks that test's BUILD ("main actor-isolated static method cannot be called
    /// from outside of the actor"), which is the compile-time guard on this regression.
    nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
#endif
