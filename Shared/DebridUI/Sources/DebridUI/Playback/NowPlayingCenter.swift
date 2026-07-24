import Foundation
#if canImport(MediaPlayer) && canImport(UIKit)
import MediaPlayer
import UIKit

/// `NowPlayingControlling` backed by MediaPlayer. Declaring these commands is what makes the
/// iPhone Remote app render a transport row with ±10s buttons and a scrubber — the same mechanism
/// YouTube uses. It also lights up Siri ("skip forward 30 seconds"), Control Center, HomePod
/// handoff and HDMI-CEC TV remotes, none of which any on-screen gesture can reach.
@MainActor
public final class NowPlayingCenter: NowPlayingControlling {
    private var handlers: NowPlayingHandlers?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?
    /// The skip interval offered to the system, in seconds. Matches the on-screen ±10s.
    private let skipInterval: Double = 10

    public init() {}

    public func activate(_ handlers: NowPlayingHandlers) {
        self.handlers = handlers
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.handlers?.play(); return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handlers?.pause(); return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handlers?.togglePlayPause(); return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? self.skipInterval
            self.handlers?.skip(interval)
            return .success
        }
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? self.skipInterval
            self.handlers?.skip(-interval)
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.handlers?.seek(e.positionTime)
            return .success
        }

        center.changePlaybackRateCommand.isEnabled = true
        center.changePlaybackRateCommand.supportedPlaybackRates = [1, 2, 3, 4].map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            self?.handlers?.setRate(Double(e.playbackRate))
            return .success
        }

        center.nextTrackCommand.isEnabled = handlers.nextTrack != nil
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let next = self?.handlers?.nextTrack else { return .noSuchContent }
            next()
            return .success
        }
    }

    public func update(_ info: NowPlayingInfo) {
        var entry: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position,
            MPNowPlayingInfoPropertyPlaybackRate: info.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let show = info.showName { entry[MPMediaItemPropertyArtist] = show }
        // Preserve artwork already resolved for this URL so each tick doesn't drop it.
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            entry[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = entry
        loadArtworkIfNeeded(info.artworkURL)
    }

    public func deactivate() {
        artworkTask?.cancel()
        artworkTask = nil
        lastArtworkURL = nil
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

    /// Fetch the poster once per URL and fold it into the existing entry.
    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != lastArtworkURL else { return }
        lastArtworkURL = url
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, self != nil,
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var entry = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            entry[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = entry
        }
    }
}
#endif
