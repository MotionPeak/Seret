import UIKit
import VLCKit
import DebridCore

/// Adapter from VLCKit to DebridCore's `VideoPlayerEngine`.
///
/// VLCKit **4.x** (Metal renderer). 3.x rendered with OpenGL ES, which touches the
/// `CAEAGLLayer` on its own render thread — tvOS 18+/26 blocks off-main-thread layer
/// access, so 3.x produced black video (`get_buffer() failed`). 4.x uses Metal
/// (`CAMetalLayer`), which has no such restriction.
///
/// 4.x also passes the new state directly to `mediaPlayerStateChanged:` (3.x passed an
/// `NSNotification` and you read `player.state`). `AsyncStream.Continuation.yield` is
/// thread-safe, so the delegate methods need no main-actor hop — events are consumed on
/// `PlayerModel`'s `@MainActor` loop.
///
/// SPIKE (M2): the rendering path is complete; track/audio/subtitle enumeration is stubbed
/// and ported to the 4.x object-based track API in M3 once on-device rendering is confirmed.
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
        for (k, v) in headers { media?.addOption(":http-\(k.lowercased())=\(v)") } // unused for RD CDN
        player.media = media
    }

    func play()  { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) { player.time = VLCTime(int: Int32(seconds * 1000)) }
    func stop()  { player.stop(); continuation.finish() }

    func addExternalSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    // SPIKE stubs — ported to the 4.x object-based track API in M3 (after rendering is confirmed).
    var audioTracks: [MediaTrack] { [] }
    var subtitleTracks: [MediaTrack] { [] }
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// 4.x state enum: no `.esAdded`/`.ended`; end-of-media surfaces as `.stopped`/`.stopping`.
    private nonisolated static func map(_ s: VLCMediaPlayerState) -> PlaybackState {
        switch s {
        case .opening, .buffering: return .buffering
        case .playing:             return .playing
        case .paused:              return .paused
        case .stopped, .stopping:  return .ended
        case .error:               return .failed("Playback failed.")
        @unknown default:          return .buffering
        }
    }
}

extension VLCKitVideoPlayerEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        continuation.yield(.state(Self.map(newState)))
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let p = aNotification.object as? VLCMediaPlayer else { return }
        let position = Double(p.time.intValue) / 1000.0
        let duration = Double(p.media?.length.intValue ?? 0) / 1000.0
        continuation.yield(.time(PlaybackTime(position: position, duration: duration)))
    }
}
