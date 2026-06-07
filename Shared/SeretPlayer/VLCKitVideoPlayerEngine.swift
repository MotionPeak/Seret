import UIKit
import DebridUI
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
/// Track enumeration/selection uses the 4.x **object-based** track API (`VLCMediaPlayerTrack`
/// with a stable `trackId`), not 3.x integer indexes. Tracks are discovered asynchronously, so
/// the delegate's `mediaPlayerTrack…` callbacks emit `.tracksChanged` and the model re-pulls.
/// The drawable handed to VLCKit. In VLCKit 4.x the player renders by **adding its own Metal render
/// view as a subview** of the drawable and sizing it from the drawable's `bounds` (see the
/// `VLCDrawable` protocol: `addSubview:` + `bounds`). We assign `player.drawable` in the engine's
/// init — before SwiftUI lays this view out — so VLCKit's render subview is created against a `.zero`
/// bounds and is NOT resized on later layout. The video then renders into a wrong-sized surface, and
/// VLCKit's default aspect-fit (`scaleFactor == 0`, "adjust to the drawable") fits into that wrong
/// size: a source smaller than the screen's pixel buffer (1080p) ends up mis-proportioned, a larger
/// one (2160p) overflows and crops.
///
/// Forcing every subview to fill our bounds — on add and on every layout pass — keeps VLCKit's
/// render surface matched to the on-screen size, so aspect-fit letterboxes correctly and self-
/// corrects across first layout, rotation, and split-view resize.
@MainActor
final class VLCDrawableView: UIView {
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.frame = bounds
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        for sub in subviews { sub.frame = bounds }
    }
}

@MainActor
final class VLCKitVideoPlayerEngine: NSObject, VideoPlayerEngine {
    let videoView: UIView = VLCDrawableView()
    private let player: VLCMediaPlayer
    private let subtitleScale: Float
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let events: AsyncStream<PlaybackEvent>

    /// `preferences` set the global subtitle look. Font + color are libvlc/freetype options that
    /// must be passed at player creation (`VLCMediaPlayer(options:)`); size is the dynamic
    /// `currentSubTitleFontScale`, applied per load. The engine is built fresh per playback, so a
    /// changed preference takes effect on the next play.
    init(preferences: SubtitlePreferences = .default) {
        var options = ["--freetype-color=\(preferences.color.rgb)"]
        if let font = preferences.font.freetypeName { options.append("--freetype-font=\(font)") }
        player = VLCMediaPlayer(options: options)
        subtitleScale = Float(preferences.size.scale)
        var cont: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
        videoView.backgroundColor = .black   // base stays black (no grey flash before VLCKit renders)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]   // track the SwiftUI host frame
        // NOTE: the actual aspect/crop fix is VLCDrawableView (above) — it keeps VLCKit's render
        // SUBVIEW matched to bounds. Assigning drawable here (pre-layout, .zero bounds) is why that
        // subview would otherwise stay mis-sized.
        player.drawable = videoView
        player.delegate = self
    }

    func load(url: URL, headers: [String: String]) {
        let media = VLCMedia(url: url)
        for (k, v) in headers { media?.addOption(":http-\(k.lowercased())=\(v)") } // unused for RD CDN
        media?.addOption(":network-caching=3000")   // buffer more for high-bitrate RD streams (fewer stalls)
        player.media = media
        player.currentSubTitleFontScale = subtitleScale   // global size preference (1.0 = VLCKit default)
    }

    func play()  { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) { player.time = VLCTime(int: Int32(seconds * 1000)) }
    func setRate(_ rate: Double) { player.rate = Float(rate) }
    func stop()  { player.stop(); continuation.finish() }

    func addExternalSubtitle(url: URL) {
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    // VLCKit 4.x object-based tracks. `trackId` is libvlc's stable string id (e.g. "audio/0",
    // "spu/1"); selecting `selectedExclusively` unselects every other track of that kind.
    var audioTracks: [MediaTrack] { player.audioTracks.map { Self.mediaTrack($0, kind: .audio) } }
    var subtitleTracks: [MediaTrack] { player.textTracks.map { Self.mediaTrack($0, kind: .subtitle) } }

    func selectAudioTrack(id: String?) {
        guard let id else { player.deselectAllAudioTracks(); return }
        player.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    func selectSubtitleTrack(id: String?) {
        guard let id else { player.deselectAllTextTracks(); return }   // nil = subtitles off
        player.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    private static func mediaTrack(_ t: VLCMediaPlayer.Track, kind: TrackKind) -> MediaTrack {
        MediaTrack(id: t.trackId, kind: kind, name: displayName(for: t), language: t.language)
    }

    /// A user-facing track label. VLCKit usually fills `trackName` ("English", "Track 1 - [eng]");
    /// fall back to the language code, then the raw id, so a row is never blank.
    private static func displayName(for t: VLCMediaPlayer.Track) -> String {
        if !t.trackName.isEmpty { return t.trackName }
        if let lang = t.language, !lang.isEmpty { return lang.uppercased() }
        return t.trackId
    }

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

    // VLCKit 4.x discovers elementary streams asynchronously and fires these as the track set
    // changes (including when an external subtitle is attached). PlayerModel re-pulls the lists.
    nonisolated func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracksChanged)
    }
    nonisolated func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracksChanged)
    }
    nonisolated func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        continuation.yield(.tracksChanged)
    }
}
