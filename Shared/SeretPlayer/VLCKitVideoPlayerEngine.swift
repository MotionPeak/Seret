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
    /// Text-track ids present before any external subtitle was attached. Anything not in here is a
    /// downloaded slave — VLCKit does not tag slave tracks itself.
    private var embeddedTextTrackIDs: Set<String> = []
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
        Self.attachVLCLogger(to: player)
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

    /// Turn on libvlc's own logging when launched with `-vlcLog`. DEBUG-only and off by default.
    ///
    /// This exists because an audio fault is invisible from our side of the seam: `PlayerModel`
    /// only ever sees `.playing` and a moving playhead, so audio that cuts in and out looks
    /// identical to audio that is fine. libvlc knows exactly what it is doing — starving, dropping
    /// to resample, restarting the output device, failing to decode a frame — and says so. Guessing
    /// from the outside costs a rebuild-and-watch cycle per guess; this costs one.
    ///
    /// Mirrors the `-uiPreview` / `-inputHUD` harness pattern already used in this app.
    /// Attach to THIS PLAYER's library, not `VLCLibrary.shared()`. `VLCMediaPlayer(options:)`
    /// builds its own libvlc instance for those options, so loggers set on the shared library see
    /// nothing but its own start-up banner — which is exactly what the first attempt captured.
    private static func attachVLCLogger(to player: VLCMediaPlayer) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-vlcLog") else { return }
        // A FILE logger, not the console one: VLCConsoleLogger's output does not reach os_log, so
        // `simctl spawn … log stream` captures nothing at all. A file in Documents can be pulled
        // straight out of the container with `simctl get_app_container … data`, on a simulator or
        // a real device via Xcode.
        guard let dir = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        else { return }
        let path = dir.appendingPathComponent("vlc.log")
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: path) else { return }
        handle.seekToEndOfFile()
        let fileLogger = VLCFileLogger.create(with: handle)
        fileLogger.level = .debug
        // Console too: its output does not reach os_log, but it DOES reach stdout, which Xcode's
        // console shows for a scheme-launched run. That is the zero-friction path — run with the
        // argument, reproduce, copy the console — with the file as the fallback for a run that
        // wasn't started from Xcode.
        let consoleLogger = VLCConsoleLogger()
        consoleLogger.level = .debug
        player.libraryInstance.loggers = [fileLogger, consoleLogger]
        #endif
    }

    func load(url: URL, headers: [String: String]) {
        // `VLCMedia(url:)` is failable (nullable initWithURL:). A malformed/empty URL yields nil;
        // without this guard `media` stays nil, `play()` no-ops, VLCKit emits no `.error`, and the
        // model would spin on the loading overlay forever. Surface a failure so it offers Retry.
        guard let media = VLCMedia(url: url) else {
            continuation.yield(.state(.failed("Could not open the media URL.")))
            return
        }
        for (k, v) in headers { media.addOption(":http-\(k.lowercased())=\(v)") } // unused for RD CDN
        // network-caching is the pre-roll VLC fills before playback starts AND after every seek —
        // it is the floor on start latency and skip latency. The RD CDN sustains high-bitrate
        // remuxes easily, so iOS runs a 1.5s pipeline for snappy starts/skips; tvOS keeps the
        // deeper 3s buffer that fixed its stalls (unchanged behavior there).
        #if os(tvOS)
        media.addOption(":network-caching=3000")
        #else
        media.addOption(":network-caching=1500")
        #endif
        media.addOption(":input-fast-seek")   // land on the nearest keyframe — skips respond fast
        media.addOption(":http-reconnect")    // transparently re-open a dropped CDN connection
        embeddedTextTrackIDs = []          // a new media has its own muxed track set
        player.media = media
        player.currentSubTitleFontScale = subtitleScale   // global size preference (1.0 = VLCKit default)
    }

    func play()  { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) { player.time = VLCTime(int: Int32(seconds * 1000)) }
    func setRate(_ rate: Double) { player.rate = Float(rate) }
    /// VLCKit's audio volume is 0…200 (100 = unity, >100 amplifies — VLC's boost). Clamp defensively.
    func setVolume(_ percent: Int) { player.audio?.volume = Int32(min(200, max(0, percent))) }
    /// Tear the session down — and make sure THIS app drops the player last.
    ///
    /// The crash it prevents accounted for 7 of the 9 crash reports on the Apple TV:
    ///
    ///     -[VLCMediaPlayer dealloc] → unregisterObservers → libvlc_media_player_unwatch_time
    ///       → vlc_player_Lock → __assert_rtn → abort,   on vlc_player_mainloop_Thread
    ///
    /// VLCKit's time-changed notification retains the player, and that notification is released
    /// when VLC's OWN mainloop thread pops its autorelease pool. `stop()` is asynchronous, so when
    /// the player screen is dismissed the view's `@State` engine — the only other strong owner —
    /// can go away while that thread still has one in flight. Its pool pop then performs the LAST
    /// release, so `dealloc` runs on the mainloop thread and re-enters a lock that thread already
    /// holds; libvlc asserts and aborts the process.
    ///
    /// Holding a strong reference past VLC's in-flight events and dropping it on the main queue
    /// guarantees our release is the last one, so `dealloc` always runs on the main thread with no
    /// lock held. `withExtendedLifetime` (not `_ = held`) because the whole point is a side effect
    /// the optimiser is otherwise free to delete.
    func stop() {
        player.delegate = nil          // no further events into a torn-down stream
        player.stop()
        continuation.finish()
        let held = player
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseGrace) {
            withExtendedLifetime(held) {}
        }
    }

    /// How long to outlive VLC's in-flight notifications before releasing the player. Generous:
    /// the cost of being wrong is an abort, and the cost of waiting is one stopped player object.
    private static let releaseGrace: TimeInterval = 3

    func addExternalSubtitle(url: URL) {
        // Snapshot the muxed ids the first time, so every id that appears afterwards is a slave.
        if embeddedTextTrackIDs.isEmpty {
            embeddedTextTrackIDs = Set(player.textTracks.map(\.trackId))
        }
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    // VLCKit 4.x object-based tracks. `trackId` is libvlc's stable string id (e.g. "audio/0",
    // "spu/1"); selecting `selectedExclusively` unselects every other track of that kind.
    var audioTracks: [MediaTrack] { player.audioTracks.map { Self.mediaTrack($0, kind: .audio) } }
    var subtitleTracks: [MediaTrack] {
        player.textTracks.map {
            Self.mediaTrack($0, kind: .subtitle,
                            isExternal: !embeddedTextTrackIDs.isEmpty
                                && !embeddedTextTrackIDs.contains($0.trackId))
        }
    }

    func selectAudioTrack(id: String?) {
        guard let id else { player.deselectAllAudioTracks(); return }
        player.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    func selectSubtitleTrack(id: String?) {
        guard let id else { player.deselectAllTextTracks(); return }   // nil = subtitles off
        player.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    private static func mediaTrack(_ t: VLCMediaPlayer.Track, kind: TrackKind,
                                   isExternal: Bool = false) -> MediaTrack {
        MediaTrack(id: t.trackId, kind: kind, name: displayName(for: t),
                   language: t.language, isExternal: isExternal,
                   codec: fourccString(t.codec),
                   channels: t.audio.map { Int($0.channelsNumber) })
    }

    /// libvlc's normalised codec id as its four printable characters ("a52 ", "trhd", "mp4a").
    ///
    /// `VLC_FOURCC` packs the first character in the LOW byte, so the bytes read out little-endian.
    /// `codec` is used rather than `fourcc` because libvlc normalises it — a container spelling
    /// AC-3 as "ac-3" still arrives here as "a52 " — which is what makes matching on it dependable.
    /// nil for anything non-printable, which ranks as `.unknown` rather than guessing.
    private static func fourccString(_ value: UInt32) -> String? {
        let bytes = [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                     UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
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
