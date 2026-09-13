import Foundation

/// The playback seam. Implemented per app target with VLCKit (`TVVLCKit` / `MobileVLCKit`); the
/// `@MainActor`, class-bound shape matches a UIKit-bound player. `DebridCore` owns only this
/// interface + the playback model — no VLCKit here. The seam also lets Stage 3 add an AVPlayer
/// fast-path behind the same protocol.
@MainActor
public protocol VideoPlayerEngine: AnyObject {
    /// Load a direct (unrestricted) media URL. `headers` are passed to the underlying player
    /// (e.g. an `Authorization` header if a source ever needs one). Resume is a deferred `seek`
    /// after playback starts (see `PlayerModel`), NOT a load-time start-time — a start-time clips
    /// the timeline so you can't rewind before the resume point.
    ///
    /// `audioLanguage` is the viewer's preferred audio language, applied BEFORE the engine opens
    /// the media so it can pick the right track during setup. That timing is the whole point:
    /// selecting a track after playback has begun makes libvlc kill the audio decoder and build a
    /// new one, which is an audible drop-out. Real releases make this routine — a REMUX whose first
    /// audio track is Spanish would otherwise start in Spanish and lurch into English.
    /// - Parameter audioTrackID: the engine-specific track to open, when this exact file has been
    ///   played before and taught us which one works. A language is the only thing libvlc's
    ///   load-time options can express about audio, and a REMUX lists its LOSSLESS track first — so
    ///   on a release carrying DTS-HD MA and AC-3 in the same language it opens the one this
    ///   hardware handles worst, and the correction afterwards costs a decoder teardown. Naming the
    ///   track removes that. nil for a file never played, which behaves exactly as before.
    func load(url: URL, headers: [String: String], audioLanguage: String?, audioTrackID: String?)
    func play()
    func pause()
    /// Halt playback and release the underlying player. After `stop()`, the engine is done —
    /// its `events` stream finishes. Called from `PlayerModel.teardown()`.
    func stop()
    func seek(to seconds: Double)
    /// Playback speed multiplier (1.0 = normal). Engines that don't support varispeed should no-op.
    func setRate(_ rate: Double)
    /// Output volume as a percentage. 100 = unity; values above 100 amplify (VLCKit supports up to
    /// 200%, like VLC's boost). Engines without software gain should no-op — hence the default below.
    func setVolume(_ percent: Int)

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(id: String?)
    func selectSubtitleTrack(id: String?)   // nil = off
    func addExternalSubtitle(url: URL)       // a downloaded subtitle temp-file URL (slice 2)

    /// Shift the displayed subtitle in time, in seconds. Positive shows each line LATER, negative
    /// earlier.
    ///
    /// The last resort when a subtitle does not match the file, and the only one available for a
    /// MUXED track: an external file can be rescaled before it is attached (`SubtitleRetimer`),
    /// but a track inside the container cannot be rewritten. It corrects a constant offset rather
    /// than a rate error, so on a drifting subtitle it buys a stretch at a time — which is still
    /// the difference between watching an episode and giving up on it.
    func setSubtitleDelay(_ seconds: Double)

    /// The playhead right now, at the engine's own resolution — NOT the figure the time
    /// notification carries.
    ///
    /// VLCKit posts `mediaPlayerTimeChanged` about once a second, so the position the model holds
    /// can be a full second stale. That is fine for a scrub bar and useless for timestamping a
    /// viewer's press against a subtitle cue: the error would be larger than the drift being
    /// corrected. libvlc itself keeps a millisecond clock and will answer at any moment.
    ///
    /// Nil when the engine cannot answer, so every caller needs a fallback.
    var preciseTime: Double? { get }

    /// The playing video's frame rate, once the engine has opened the media (nil before that, or
    /// when the engine can't report it). Subtitle matching needs it: a file timed against a
    /// different rate drifts linearly — right at the start, then progressively early until each
    /// cue is clipped by its successor. `SubtitleMatch` scores that mismatch, but only when it is
    /// told the real rate.
    var videoFPS: Double? { get }

    /// Time + state updates as the engine produces them.
    var events: AsyncStream<PlaybackEvent> { get }

    /// Write one line into whatever diagnostics log this engine keeps.
    ///
    /// The VLCKit engine already writes every play to `Library/Caches/vlc.log`, which is how a
    /// living-room fault gets diagnosed without reproducing it. The APP's decisions were invisible
    /// there, and the subtitle ones are exactly what a report needs: five plays on the Apple TV
    /// showed not one `add subtitle` line, which is what said the download path was never running
    /// at all — but nothing in the file could say WHY. Now it can.
    func note(_ line: String)
}

public extension VideoPlayerEngine {
    /// Engines that cannot shift subtitles simply ignore the request.
    func setSubtitleDelay(_ seconds: Double) {}
}

public extension VideoPlayerEngine {
    /// Default: engines without software volume gain ignore the request (also keeps existing test
    /// fakes source-compatible without a stub).
    func setVolume(_ percent: Int) {}

    /// Default: an engine that can't report a frame rate degrades to "unknown", which makes
    /// subtitle ranking skip the fps term rather than penalise every candidate.
    var videoFPS: Double? { nil }

    /// Default: an engine with no finer clock than its own notifications says so, and callers fall
    /// back to the last reported position.
    var preciseTime: Double? { nil }

    /// Default: an engine that keeps no log drops the line (every test fake, and any future
    /// AVPlayer fast-path that has nowhere to write).
    func note(_ line: String) {}
}
