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
    func load(url: URL, headers: [String: String])
    func play()
    func pause()
    /// Halt playback and release the underlying player. After `stop()`, the engine is done —
    /// its `events` stream finishes. Called from `PlayerModel.teardown()`.
    func stop()
    func seek(to seconds: Double)
    /// Playback speed multiplier (1.0 = normal). Engines that don't support varispeed should no-op.
    func setRate(_ rate: Double)

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(id: String?)
    func selectSubtitleTrack(id: String?)   // nil = off
    func addExternalSubtitle(url: URL)       // a downloaded subtitle temp-file URL (slice 2)

    /// Time + state updates as the engine produces them.
    var events: AsyncStream<PlaybackEvent> { get }
}
