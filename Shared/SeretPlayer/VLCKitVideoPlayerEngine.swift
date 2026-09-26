#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import DebridUI
import VLCKit
import DebridCore
import os

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
#if canImport(UIKit)
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

/// The view type VLCKit renders into on this platform.
typealias PlatformVideoView = UIView
#else
/// The AppKit twin. VLCKit 4's macOS drawable contract is the same `addSubview:` + `bounds` pair, so
/// the same fix applies: force every subview to fill our bounds, on add and on every layout pass.
@MainActor
final class VLCDrawableView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor   // no flash of window colour before VLC draws
    }

    required init?(coder: NSCoder) { fatalError("VLCDrawableView is created in code") }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        subview.frame = bounds
        subview.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        for sub in subviews { sub.frame = bounds }
    }
}

/// The view type VLCKit renders into on this platform.
typealias PlatformVideoView = NSView
#endif

@MainActor
final class VLCKitVideoPlayerEngine: NSObject, VideoPlayerEngine {
    let videoView: PlatformVideoView = VLCDrawableView(frame: .zero)
    private let player: VLCMediaPlayer
    private let subtitleScale: Float
    /// Text-track ids present before any external subtitle was attached. Anything not in here is a
    /// downloaded slave — VLCKit does not tag slave tracks itself.
    private var embeddedTextTrackIDs: Set<String> = []
    /// Whether the muxed-track snapshot has been TAKEN, which is not the same as its being
    /// non-empty. A file with no muxed text tracks snapshots to the empty set, and reading
    /// emptiness as "not yet taken" is what made a subtitle downloaded for such a file report
    /// itself as muxed — so it was listed among the media's own tracks instead of as the one the
    /// viewer had just fetched.
    private var embeddedSnapshotTaken = false
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    let events: AsyncStream<PlaybackEvent>

    /// What the APP last asked for — not what libvlc reports.
    ///
    /// A frame step (see `seek`) makes libvlc announce `.playing` for the duration of the step even
    /// though the viewer is paused. Forwarding that would tell the UI playback resumed, and on tvOS
    /// that hides the scrub bar and disarms the very scrub the viewer is aiming with. Where the two
    /// disagree, the app's intent wins.
    ///
    /// Locked rather than plain state because `mediaPlayerStateChanged` is `nonisolated` — VLCKit
    /// makes no promise about which thread delivers it.
    private let playbackRequested = OSAllocatedUnfairLock(initialState: false)

    /// The diagnostics log this engine and its libvlc write to — `Library/Caches/vlc.log` — or nil
    /// when nowhere writable exists. Read from libvlc's threads and the delegate as well as the main
    /// actor; a `FileHandle` append is one `write(2)`, which is safe enough for a log.
    private let diagnosticsHandle: FileHandle?
    /// The last raw VLC state written to the log. libvlc reports `.buffering` once per percent of
    /// a fill — fifty identical lines per start — so only a CHANGE of state is worth a marker; the
    /// percentages are already in libvlc's own lines beside it.
    private let lastLoggedState = OSAllocatedUnfairLock(initialState: Int(-1))

    /// `preferences` set the global subtitle look. Font + color are libvlc/freetype options that
    /// must be passed at player creation (`VLCMediaPlayer(options:)`); size is the dynamic
    /// `currentSubTitleFontScale`, applied per load. The engine is built fresh per playback, so a
    /// changed preference takes effect on the next play.
    init(preferences: SubtitlePreferences = .default, extraOptions: [String] = []) {
        var options = ["--freetype-color=\(preferences.color.rgb)"]
        if let font = preferences.font.freetypeName { options.append("--freetype-font=\(font)") }
        #if os(macOS)
        // HDR (PQ / Dolby Vision) films played at under half brightness on the Mac. libvlc's
        // OpenGL output tone-maps them to an SDR surface with its default spline curve against a
        // 203-nit reference white, so a scene mastered at 100 nits lands at ~49 % — measured on an
        // HDR10 test clip at mean 57.6 vs 128.7 for the same picture in SDR. `linear` (function 7)
        // with a 2× gain brings it to 127.9 and leaves SDR untouched (128.7). The values are
        // integers: libvlc silently ignores the names ("clip", "linear").
        options += ["--gl-tone-mapping-function=7", "--gl-tone-mapping-param=2.0"]
        // Subtitles: libvlc's default is a heavy black outline plus a hard offset shadow. The
        // approved look is a soft shadow with no box; a thin, semi-opaque outline and a close,
        // softer shadow are as near as freetype gets (it cannot blur, and `--freetype-bold` has
        // no effect in this build — checked by screenshot against the default).
        options += ["--freetype-outline-thickness=2", "--freetype-outline-opacity=170",
                    "--freetype-shadow-opacity=200", "--freetype-shadow-distance=0.04"]
        #endif
        let prefetch = Self.prefetchOptions()
        options += prefetch
        options += extraOptions
        player = VLCMediaPlayer(options: options)
        let handle = DiagnosticsLog.shared.prepare()
        diagnosticsHandle = handle
        Self.attachVLCLogger(to: player, file: handle)
        subtitleScale = Float(preferences.size.scale)
        var cont: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
        #if canImport(UIKit)
        videoView.backgroundColor = .black   // base stays black (no grey flash before VLCKit renders)
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]   // track the SwiftUI host frame
        #else
        videoView.autoresizingMask = [.width, .height]   // the drawable paints its own black layer
        #endif
        // NOTE: the actual aspect/crop fix is VLCDrawableView (above) — it keeps VLCKit's render
        // SUBVIEW matched to bounds. Assigning drawable here (pre-layout, .zero bounds) is why that
        // subview would otherwise stay mis-sized.
        player.drawable = videoView
        player.delegate = self
        note("player \(prefetch.joined(separator: " "))")   // which read-ahead this log was made with
    }

    /// libvlc's read-ahead in front of the Real-Debrid connection — the `prefetch` stream filter,
    /// which is the only cache between the demuxer and the network.
    ///
    /// This, not `:network-caching`, is what a skip waits on. The iPad's vlc.log (111 real seeks)
    /// put 79% of every skip's wait in the demuxer's seek, and all of that is network reads:
    /// - RD's server answers `Connection: close`, and libvlc asks for open-ended ranges, so every
    ///   reposition is a new TCP + TLS connection plus ~200ms before RD's first byte — ~460ms a hop.
    /// - An MKV seek is not one reposition. The demuxer hops back and forth to find a keyframe for
    ///   every track, and one 10s rewind took 230 of those hops (108s).
    /// - libvlc's defaults turn nearly every hop into a reconnect. A 16 MiB buffer is ~1.5s of a
    ///   4K remux, so any skip lands outside it; and a forward hop more than 16 KiB past the bytes
    ///   already downloaded reconnects rather than waiting for the connection that is streaming.
    ///
    /// `prefetchBufferKiB`: forward skips inside the read-ahead are served from memory with no
    /// network at all. 128 MiB is about ten seconds of an 80 Mbps remux and a good deal more of
    /// everything lighter. It is allocated up front, and on the Apple TV playback measured 457 MB
    /// on the device with jetsam never choosing Seret at ~830 MB, so this fits.
    ///
    /// `prefetchSeekThresholdBytes`: a forward hop within this many bytes of the downloaded edge
    /// reads through on the live connection instead of opening a new one. This is what tames the
    /// demuxer's hunt for a keyframe, which walks back and forth over the same few megabytes.
    ///
    /// Measured A/B in the tvOS simulator on the file behind the 108s report (The Shining, N0DS13),
    /// same skips, libvlc's defaults vs these:
    /// - +10s skip: 2.8–3.7s → 0.1s (served from memory, no connection at all)
    /// - a rewind landing in a 10s gap between keyframes: 72 connections / 35.4s → 5 / 4.7s
    /// - a plain rewind: unchanged at ~2s, for the reason below
    ///
    /// What neither can do: survive a BACKWARD jump past the buffer's start. `prefetch` resets on
    /// one and reconnects, and it discards already-played data whenever read-ahead needs the room,
    /// so a rewind always goes to the network.
    static let prefetchBufferKiB = 128 * 1024
    static let prefetchSeekThresholdBytes = 8 << 20
    /// libvlc's own buffer for a stream the app's cache is already serving (see `load`).
    static let proxiedPrefetchKiB = 16 * 1024

    /// DEBUG `-prefetchKiB <KiB>` / `-prefetchThreshold <bytes>` override the two, so a run can be
    /// compared against another without a rebuild. `-prefetchKiB 16384 -prefetchThreshold 16384`
    /// is libvlc's own default and so reproduces the old behaviour.
    private static func prefetchOptions() -> [String] {
        var kib = prefetchBufferKiB
        var threshold = prefetchSeekThresholdBytes
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> Int? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return Int(args[i + 1])
        }
        kib = value(after: "-prefetchKiB") ?? kib
        threshold = value(after: "-prefetchThreshold") ?? threshold
        #endif
        return ["--prefetch-buffer-size=\(kib)", "--prefetch-seek-threshold=\(threshold)"]
    }

    /// Route libvlc's own log into the diagnostics file — always — and to the console under
    /// `-vlcLog` (DEBUG).
    ///
    /// This exists because an audio fault is invisible from our side of the seam: `PlayerModel`
    /// only ever sees `.playing` and a moving playhead, so audio that cuts in and out looks
    /// identical to audio that is fine. libvlc knows exactly what it is doing — starving, dropping
    /// to resample, restarting the output device, failing to decode a frame — and says so.
    ///
    /// It used to be entirely opt-in, which meant every report from the living room arrived with
    /// no evidence: the fault had happened on a Tuesday night on a file nobody could name, and
    /// reproducing it on demand — the only way to get a `-vlcLog` run — kept failing. So the file
    /// is written on every play, at debug level (the lines that matter — `killing decoder`,
    /// `Buffering 0%`, `ES track selected` — are debug lines), and rotated by `openDiagnosticsLog`
    /// so it can never grow past two files. Steady-state playback is quiet, so a two-hour film
    /// costs a few hundred kilobytes.
    ///
    /// Two gotchas, each of which cost a build:
    /// - Attach to THIS PLAYER's library, not `VLCLibrary.shared()`. `VLCMediaPlayer(options:)`
    ///   builds its own libvlc instance for those options, so loggers set on the shared library see
    ///   nothing but its own start-up banner.
    /// - The console logger does not reach os_log, so `log stream` captures nothing — but it DOES
    ///   reach stdout, which both Xcode's console and `devicectl device process launch --console`
    ///   show. The file is the answer for a run that was not started from a console.
    private static func attachVLCLogger(to player: VLCMediaPlayer, file: FileHandle?) {
        var loggers: [VLCLogging] = []
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-vlcLog") {
            let consoleLogger = VLCConsoleLogger()
            consoleLogger.level = .debug
            loggers.append(consoleLogger)
        }
        #endif
        if let file {
            let fileLogger = VLCFileLogger.create(with: file)
            fileLogger.level = .debug
            fileLogger.formatter = TimestampedLogFormatter()
            loggers.append(fileLogger)
        }
        guard !loggers.isEmpty else { return }
        player.libraryInstance.loggers = loggers
    }

    func load(url: URL, headers: [String: String], audioLanguage: String?, audioTrackID: String?) {
        // `VLCMedia(url:)` is failable (nullable initWithURL:). A malformed/empty URL yields nil;
        // without this guard `media` stays nil, `play()` no-ops, VLCKit emits no `.error`, and the
        // model would spin on the loading overlay forever. Surface a failure so it offers Retry.
        guard let media = VLCMedia(url: url) else {
            continuation.yield(.state(.failed("Could not open the media URL.")))
            return
        }
        // The file name only — never the URL, which carries the unrestricted RD token.
        note("load \(url.lastPathComponent) audio-language=\(audioLanguage ?? "-") audio-track-id=\(audioTrackID ?? "-")")
        for (k, v) in headers { media.addOption(":http-\(k.lowercased())=\(v)") } // unused for RD CDN
        // network-caching becomes libvlc's `pts_delay`: the depth filled before playback starts,
        // after every seek, AND after every clock reset.
        //
        // It is NOT the lever for the periodic mid-film freeze, and that is settled rather than
        // assumed. Raising tvOS 2000 → 3000 to chase that bug changed nothing on the device, and
        // `-vlcLog` then showed why — the freeze is `ES_OUT_RESET_PCR`, a clock reset that late
        // pictures provoke, and the refill it forces is this depth. So a DEEPER buffer makes every
        // freeze LONGER. Both platforms now run the same 1.5s: it halves how long each stall lasts
        // and makes skips twice as responsive, and the 3s experiment is the evidence that input
        // starvation is not what is happening (a starved pipeline would have improved).
        //
        // Fix the LATE PICTURES, not this number. Both directions have now been tried.
        media.addOption(":network-caching=1500")
        // DEBUG `-noFastSeek` drops this, so a run with and a run without can be compared. Fast
        // seek lands on the nearest KEYFRAME rather than seeking precisely, which is the standing
        // suspect for "skip a long way and it doesn't drop you off at that point".
        if !ProcessInfo.processInfo.arguments.contains("-noFastSeek") {
            media.addOption(":input-fast-seek")   // land on the nearest keyframe — skips respond fast
        }
        media.addOption(":http-reconnect")    // transparently re-open a dropped CDN connection
        // Through the app's stream cache, libvlc's reconnects cost nothing and the cache does the
        // read-ahead — so libvlc keeps its own 16 MiB default instead of a second 128 MiB copy of
        // what the cache already holds in RAM.
        if url.host == "127.0.0.1" { media.addOption(":prefetch-buffer-size=\(Self.proxiedPrefetchKiB)") }
        // Pick the audio track HERE, during setup, rather than switching after playback starts.
        // libvlc's own log made the cost plain: a REMUX whose first audio track is Spanish
        // ("Track Language=`spa'", "Track Name=Latino") began decoding Spanish, then our late
        // selection killed the decoder and rebuilt it for English — `killing decoder` →
        // `removing "audio decoder"` → `codec (ac3) started`, three times before the film had
        // begun. Every one of those is silence. Told up front, libvlc simply opens the right track.
        if let audioLanguage { media.addOption(":audio-language=\(audioLanguage)") }
        // …and when this file has been played before, name the exact track rather than a language.
        // A language is all libvlc can be told about audio otherwise, and a REMUX lists its
        // LOSSLESS track first — so it opens DTS-HD MA, the model corrects it to the AC-3 track a
        // moment later, and that correction is a `killing decoder` → rebuild. Measured on the Apple
        // TV: naming the track takes that from 1 teardown to 0, and the audio decoders built during
        // startup from 4 to 2. The id is libvlc 4's STRING form ("audio/3") — the integer ES id the
        // option historically took does nothing here, which is why it is passed through verbatim
        // rather than parsed.
        if let audioTrackID { media.addOption(":audio-track-id=\(audioTrackID)") }
        Self.applyAudioTrackProbe(to: media)
        embeddedTextTrackIDs = []          // a new media has its own muxed track set
        embeddedSnapshotTaken = false
        player.media = media
        player.currentSubTitleFontScale = subtitleScale   // global size preference (1.0 = VLCKit default)
    }

    /// DEBUG: force a specific audio track at LOAD time, whatever the ranking would choose.
    ///
    /// This is how `:audio-track-id` was shown to work at all before anything was built on it —
    /// libvlc 4 identifies tracks by STRING ("audio/3") while that option historically took an
    /// integer ES id, and only the string form bites. It stays because it is the way to answer
    /// "would this file be fine on its other track?" for a report about wrong or missing audio,
    /// without having to play the file first to teach the preference store. Each candidate costs a
    /// run, not a rebuild:
    ///
    ///     … -- -vlcLog -autoPlay -audioTrackID 3
    ///     … -- -vlcLog -autoPlay -audioTrackID audio/3
    ///     … -- -vlcLog -autoPlay -audioTrackIndex 1
    ///
    /// A working form shows `ES track selected: 'audio/3'` up front and NO `killing decoder`.
    private static func applyAudioTrackProbe(to media: VLCMedia) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let id = value(after: "-audioTrackID") {
            media.addOption(":audio-track-id=\(id)")
            print("[audio] probe :audio-track-id=\(id)")
        }
        if let index = value(after: "-audioTrackIndex") {
            media.addOption(":audio-track=\(index)")
            print("[audio] probe :audio-track=\(index)")
        }
        #endif
    }

    func play()  { playbackRequested.withLock { $0 = true };  note("play");  player.play() }
    func pause() { playbackRequested.withLock { $0 = false }; note("pause"); player.pause() }

    /// Seek, and — when paused — force the target frame onto the screen.
    ///
    /// Setting `time` moves the demuxer but does NOT render while paused: the vout keeps displaying
    /// the last decoded picture. That is why a ±10s skip on a paused film moved the scrub bar and
    /// left the image frozen — the seek landed, nothing drew it. One frame step decodes and
    /// displays the seek target and leaves the player paused.
    ///
    /// Gated on BOTH the app's intent and libvlc's own state, so a resume-seek issued while the
    /// media is still opening cannot trip it.
    func seek(to seconds: Double) {
        // `Int32(Double)` TRAPS on NaN, on infinity and on anything past ~24.8 days of milliseconds.
        // Every caller clamps to the media's length today, but this is the hottest path in the app
        // and the failure mode is an uncatchable crash, so the conversion defends itself: a resume
        // point restored from a corrupt store, or a length VLCKit has not reported yet, must land
        // somewhere sane rather than kill the process.
        let ms = (seconds * 1000).isFinite ? min(max(seconds * 1000, 0), Double(Int32.max)) : 0
        note("seek → \(Int(ms) / 1000)s (from \(player.time.intValue / 1000)s)")
        player.time = VLCTime(int: Int32(ms))
        guard !playbackRequested.withLock({ $0 }), player.state == .paused else { return }
        player.gotoNextFrame()
    }
    func setRate(_ rate: Double) { note("rate \(rate)"); player.rate = Float(rate) }
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
        note("stop at \(player.time.intValue / 1000)s")
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
        if !embeddedSnapshotTaken {
            embeddedTextTrackIDs = Set(player.textTracks.map(\.trackId))
            embeddedSnapshotTaken = true
        }
        note("add subtitle \(url.lastPathComponent)")
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    /// libvlc holds the subtitle offset in MICROseconds, and positive means "show it later" —
    /// the same sign convention this protocol uses, so the only conversion is the scale.
    func setSubtitleDelay(_ seconds: Double) {
        let micros = seconds * 1_000_000
        // `NSInteger(Double)` traps on NaN and on infinity, and this value reaches here from a UI
        // control. Clamp rather than risk an uncatchable crash mid-playback.
        guard micros.isFinite else { return }
        player.currentVideoSubTitleDelay = Int(min(max(micros, -3_600_000_000), 3_600_000_000))
    }

    // VLCKit 4.x object-based tracks. `trackId` is libvlc's stable string id (e.g. "audio/0",
    // "spu/1"); selecting `selectedExclusively` unselects every other track of that kind.
    /// The playing video's frame rate, as a rational — libvlc reports numerator and denominator,
    /// so 24000/1001 stays exactly 23.976 instead of rounding to 24. That precision is the point:
    /// subtitle matching compares against a file's declared fps, and 23.976 vs 24 is the classic
    /// drift pair. nil before the media opens, or when the track reports no rate.
    var videoFPS: Double? {
        guard let video = player.videoTracks.first?.video else { return nil }
        let denominator = video.frameRateDenominator
        guard video.frameRate > 0, denominator > 0 else { return nil }
        return Double(video.frameRate) / Double(denominator)
    }

    var preciseTime: Double? {
        // `VLCTime.intValue` is milliseconds. Zero and negative both mean "no answer yet" here:
        // libvlc reports 0 before the clock starts, and at a genuine time zero the caller's
        // fallback — a position of 0 — is the same number anyway.
        let ms = player.time.intValue
        return ms > 0 ? Double(ms) / 1000 : nil
    }

    var audioTracks: [MediaTrack] { player.audioTracks.map { Self.mediaTrack($0, kind: .audio) } }
    var subtitleTracks: [MediaTrack] {
        player.textTracks.map {
            Self.mediaTrack($0, kind: .subtitle,
                            isExternal: embeddedSnapshotTaken
                                && !embeddedTextTrackIDs.contains($0.trackId))
        }
    }

    func selectAudioTrack(id: String?) {
        note("select audio \(id ?? "none")")
        guard let id else { player.deselectAllAudioTracks(); return }
        player.audioTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    func selectSubtitleTrack(id: String?) {
        note("select subtitle \(id ?? "off")")
        guard let id else { player.deselectAllTextTracks(); return }   // nil = subtitles off
        player.textTracks.first { $0.trackId == id }?.isSelectedExclusively = true
    }

    private static func mediaTrack(_ t: VLCMediaPlayer.Track, kind: TrackKind,
                                   isExternal: Bool = false) -> MediaTrack {
        MediaTrack(id: t.trackId, kind: kind, name: displayName(for: t),
                   language: t.language, isExternal: isExternal,
                   codec: fourccString(t.codec),
                   channels: t.audio.map { Int($0.channelsNumber) },
                   isSelected: t.isSelected)
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
        // A frame step announces `.playing` mid-pause (see `seek` / `playbackRequested`). Taken at
        // face value it reads as "the viewer resumed" and tears down the paused UI underneath them,
        // so intent wins — the rule itself is pure and lives in DebridCore.
        let state = Self.map(newState).reconciled(playbackRequested: playbackRequested.withLock { $0 })
        let repeated = lastLoggedState.withLock { last -> Bool in
            defer { last = newState.rawValue }
            return last == newState.rawValue
        }
        if !repeated { note("state \(Self.name(of: newState)) → \(state)") }
        continuation.yield(.state(state))
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

// MARK: - Diagnostics log

extension VLCKitVideoPlayerEngine {
    /// Where every play leaves its trace: `Library/Caches/vlc.log`, with the previous generation in
    /// `vlc.previous.log`. Caches, not Documents — it is the location that actually exists on
    /// tvOS, and it still sits inside the app data container, so
    /// `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
    /// --domain-identifier com.solomons.seret.tv --source Library/Caches/vlc.log --destination …`
    /// reaches it with no console attached and nothing to reproduce. tvOS may purge Caches under
    /// pressure, which is acceptable for a diagnostic.
    nonisolated static let diagnosticsFileName = "vlc.log"
    nonisolated static let previousDiagnosticsFileName = "vlc.previous.log"
    /// Rotate above this size. A two-hour film with a few seeks writes a few hundred kilobytes, so
    /// two files hold the last several sessions; a pathological loop (an audio output failing
    /// thirty times a second) still cannot grow past twice this.
    nonisolated static let diagnosticsRotateBytes: UInt64 = 4 << 20

    /// Open the log for appending, rotating first when it has grown past the cap. nil when the
    /// app has nowhere writable, in which case there is simply no file log.
    nonisolated static func openDiagnosticsLog() -> FileHandle? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true) else { return nil }
        let url = dir.appendingPathComponent(diagnosticsFileName)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
           size > diagnosticsRotateBytes {
            let previous = dir.appendingPathComponent(previousDiagnosticsFileName)
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: url, to: previous)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    /// One app-side line beside libvlc's own — what the engine was ASKED to do, so a `Buffering 0%`
    /// can be read as "after that seek" rather than guessed at. `nonisolated` because the delegate
    /// reports state changes from VLC's threads. `write(contentsOf:)` throws rather than raising,
    /// so a full disk costs a dropped line, not the process.
    nonisolated func note(_ line: String) {
        DiagnosticsLog.shared.write("[seret] \(line)")
    }

    /// `DateFormatter` is documented thread-safe for formatting once configured; it is never
    /// mutated after this.
    nonisolated private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    nonisolated static func timestamp() -> String { stamp.string(from: Date()) }

    nonisolated static func name(of state: VLCMediaPlayerState) -> String {
        switch state {
        case .opening: return "opening"
        case .buffering: return "buffering"
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopping: return "stopping"
        case .stopped: return "stopped"
        case .error: return "error"
        @unknown default: return "state(\(state.rawValue))"
        }
    }
}

/// libvlc's default file formatter carries no time at all, and the file has to make sense weeks
/// later beside the engine's own markers. Same shape as the console lines, minus the process id.
private final class TimestampedLogFormatter: NSObject, VLCLogMessageFormatting {
    var contextFlags: VLCLogContextFlag = []
    var customContext: Any?

    func format(withMessage message: String, logLevel level: VLCLogLevel,
                context: VLCLogContext?) -> String {
        let tag: String
        switch level {
        case .error: tag = "ERR"
        case .warning: tag = "WARN"
        case .info: tag = "INFO"
        default: tag = "DBG"
        }
        // No module name: libvlc reports "libvlc" for every line here, so it carried nothing.
        return "\(VLCKitVideoPlayerEngine.timestamp()) [\(tag)] \(message)\n"
    }
}
