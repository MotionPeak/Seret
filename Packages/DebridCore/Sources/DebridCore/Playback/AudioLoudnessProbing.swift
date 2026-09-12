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
    /// RMS of the whole mix, per frame.
    public let frames: [Float]
    /// RMS of the CENTRE channel alone, band-limited to the speech range — the signal that tells
    /// dialogue from everything else, since a film mix puts voices there and spreads music and
    /// effects across the rest. Empty when the source gave no usable centre.
    public let centre: [Float]
    /// DEBUG: per-frame RMS for every channel, so "which channel tracks the subtitles" is a
    /// question that can be answered rather than assumed.
    public let perChannel: [[Float]]
    public let startSeconds: Double
    public init(frames: [Float], centre: [Float] = [], perChannel: [[Float]] = [],
                startSeconds: Double) {
        self.frames = frames
        self.centre = centre
        self.perChannel = perChannel
        self.startSeconds = startSeconds
    }
}

@MainActor
public protocol AudioLoudnessProbing: AnyObject {
    /// Mean loudness per `SubtitleSync` frame (100ms) for roughly `seconds` of audio beginning at
    /// `from`. Empty when nothing could be decoded — a dead link, a refused range request, a
    /// container the decoder will not open.
    func loudness(url: URL, from startSeconds: Double, seconds: Double) async -> LoudnessWindow?
    /// How much audio has been gathered so far, in seconds of film. Read while `loudness` is still
    /// running, so a measurement that takes minutes can show its progress rather than appearing to
    /// hang. 0 before anything arrives.
    var measuredSeconds: Double { get }
    /// Abandon a probe in flight. Called when the viewer leaves, so a measurement cannot outlive
    /// the thing it was measuring.
    func cancel()
}

public extension AudioLoudnessProbing {
    /// A probe that cannot report progress simply reports none; the caller shows an indeterminate
    /// state rather than a wrong number.
    var measuredSeconds: Double { 0 }
}
