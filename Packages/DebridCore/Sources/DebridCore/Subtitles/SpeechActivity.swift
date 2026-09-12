import Foundation

/// Turns a loudness-per-frame signal from the audio into the same "is something happening here"
/// shape `SubtitleTiming.activity` produces from cues, so the two can be correlated.
///
/// Deliberately not a real voice-activity detector. A VAD distinguishes speech from music; what
/// this needs is only to find the frames that stand out from the bed, because a subtitle cue
/// coincides with those whether the sound under it is a voice or not. That keeps it pure Swift
/// with no model, no framework and no tuning per title — and `SubtitleSync` already refuses an
/// answer it cannot support, so a noisy signal costs a declined estimate rather than a wrong one.
public enum SpeechActivity {

    /// Frames louder than the material's own floor, as 1s and 0s.
    ///
    /// The threshold is taken from the signal rather than fixed, because loudness alone says
    /// nothing: a film is rarely silent, and an absolute cut-off would mark a whole score as
    /// speech on one mix and nothing at all on another. The floor is a low percentile of the
    /// frames present — what this material sounds like when nobody is talking — and the bar sits a
    /// fixed fraction of the way from there to the loud end.
    public static func fromLoudness(_ frames: [Float], quietPercentile: Double = 0.2,
                                    loudPercentile: Double = 0.95,
                                    fraction: Double = 0.35) -> [Float] {
        guard !frames.isEmpty else { return [] }
        let sorted = frames.sorted()
        let floor = Double(percentile(sorted, quietPercentile))
        let ceiling = Double(percentile(sorted, loudPercentile))
        // A flat signal has no floor to stand above. Reporting all of it as speech would let a
        // uniformly loud passage outvote the dialogue underneath it.
        guard ceiling - floor > 0.0001 else { return [Float](repeating: 0, count: frames.count) }
        let threshold = Float(floor + (ceiling - floor) * fraction)
        return frames.map { $0 > threshold ? 1 : 0 }
    }

    /// The loudest `fraction` of frames, marked as speech.
    ///
    /// Preferred over a threshold picked in the abstract, because the caller knows something the
    /// audio does not: how much of this window the SUBTITLE says is dialogue. Matching the two
    /// densities makes the signals comparable by construction, which is the whole business of
    /// correlating them.
    ///
    /// The fixed-threshold version measured a real film at 26% speech against a subtitle claiming
    /// 64% — two signals of such different weight that the best alignment scored 0.20 and sat 85
    /// seconds from the truth. Telling it how much to look for is what closes that gap.
    public static func densest(_ frames: [Float], fraction: Double) -> [Float] {
        guard !frames.isEmpty else { return [] }
        let wanted = Int((Double(frames.count) * min(max(fraction, 0.02), 0.9)).rounded())
        guard wanted > 0, wanted < frames.count else {
            return [Float](repeating: 0, count: frames.count)
        }
        // The loudness of the quietest frame that still counts.
        let cutoff = frames.sorted()[frames.count - wanted]
        guard cutoff > frames.min()! else {
            return [Float](repeating: 0, count: frames.count)   // flat: nothing stands out
        }
        return frames.map { $0 >= cutoff ? 1 : 0 }
    }

    private static func percentile(_ sorted: [Float], _ p: Double) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let i = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(i, 0), sorted.count - 1)]
    }
}
