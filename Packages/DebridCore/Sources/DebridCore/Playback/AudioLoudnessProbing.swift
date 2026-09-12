import Foundation

/// Reads how loud a window of a media's audio is, frame by frame — the signal subtitle auto-sync
/// lines cues up against.
///
/// A seam, for the same reason `VideoPlayerEngine` is one: the only way to get decoded audio is
/// through libvlc, which is platform code and must not reach into `DebridCore`. It also means the
/// sync logic is testable with a canned signal instead of a network stream.
/// Loudness frames and — load-bearing — the media time the FIRST of them corresponds to.
///
/// The caller cannot assume it got the window it asked for. `:start-time` is silently ignored on a
/// network stream, and a seek lands where the container's keyframes allow; believing the request
/// instead of the answer compared minute 24's subtitles against the opening titles and produced a
/// confident sixty-three-second correction out of nothing.
public struct LoudnessWindow: Sendable {
    public let frames: [Float]
    public let startSeconds: Double
    public init(frames: [Float], startSeconds: Double) {
        self.frames = frames
        self.startSeconds = startSeconds
    }
}

@MainActor
public protocol AudioLoudnessProbing: AnyObject {
    /// Mean loudness per `SubtitleSync` frame (100ms) for roughly `seconds` of audio beginning at
    /// `from`. Empty when nothing could be decoded — a dead link, a refused range request, a
    /// container the decoder will not open.
    func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow?
    /// Abandon a probe in flight. Called when the viewer leaves, so a measurement cannot outlive
    /// the thing it was measuring.
    func cancel()
}
