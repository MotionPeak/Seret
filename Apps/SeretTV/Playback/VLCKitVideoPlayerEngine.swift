import UIKit
import TVVLCKit
import DebridCore

@MainActor
final class VLCKitVideoPlayerEngine: NSObject, VideoPlayerEngine {
    let videoView = UIView()
    private let player = VLCMediaPlayer()
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let events: AsyncStream<PlaybackEvent>

    override init() {
        var cont: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
        player.drawable = videoView
        player.delegate = self
    }

    func load(url: URL, headers: [String: String]) {
        let media = VLCMedia(url: url)
        for (k, v) in headers { media.addOption(":http-\(k.lowercased())=\(v)") } // RD CDN needs no headers today; passthrough kept for a future auth-header source.
        player.media = media
    }

    func play()  { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.time = VLCTime(int: Int32(seconds * 1000))
    }

    // Track id == the VLCKit integer index rendered as a String.
    var audioTracks: [MediaTrack] {
        tracks(indexes: player.audioTrackIndexes,
               names: player.audioTrackNames,
               kind: .audio)
    }

    var subtitleTracks: [MediaTrack] {
        tracks(indexes: player.videoSubTitlesIndexes,
               names: player.videoSubTitlesNames,
               kind: .subtitle)
    }

    // `id` must be the numeric track index String produced by `tracks(...)`; nil or non-numeric → off (-1).
    func selectAudioTrack(id: String?) {
        player.currentAudioTrackIndex = Int32(id ?? "") ?? -1
    }

    func selectSubtitleTrack(id: String?) {
        player.currentVideoSubTitleIndex = Int32(id ?? "") ?? -1
    }

    func addExternalSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    private func tracks(indexes: [Any], names: [Any], kind: TrackKind) -> [MediaTrack] {
        zip(indexes, names).compactMap { idx, name in
            guard let i = (idx as? NSNumber)?.intValue, i >= 0 else { return nil } // -1 == "Disable"
            let label = (name as? String) ?? "Track \(i)"
            return MediaTrack(id: String(i), kind: kind, name: label, language: nil)
        }
    }
}

extension VLCKitVideoPlayerEngine: VLCMediaPlayerDelegate {
    // VLCKit 3.x (UIKit-bound) delivers these callbacks on the main thread, so assumeIsolated
    // lets us read the @MainActor player and yield synchronously — preserving event order with
    // no per-tick Task allocation. (Traps loudly if VLCKit's threading ever changes.)
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        MainActor.assumeIsolated {
            switch player.state {
            case .opening, .buffering, .esAdded: continuation.yield(.state(.buffering))
            case .playing:                       continuation.yield(.state(.playing))
            case .paused:                        continuation.yield(.state(.paused))
            case .stopped, .ended:               continuation.yield(.state(.ended))
            case .error:                         continuation.yield(.state(.failed("Playback failed.")))
            @unknown default:                    break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        MainActor.assumeIsolated {
            let position = Double(player.time.intValue) / 1000.0
            let duration = Double(player.media?.length.intValue ?? 0) / 1000.0
            continuation.yield(.time(PlaybackTime(position: position, duration: duration)))
        }
    }
}
