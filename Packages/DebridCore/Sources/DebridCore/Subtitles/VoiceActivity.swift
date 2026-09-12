import Foundation

/// How likely each frame is to be someone talking, rather than merely loud.
///
/// This exists because loudness failed, and failed in the worst way: measured against a subtitle
/// that was verifiably correct, a loudness envelope scored -0.13 at the true alignment and +0.29 at
/// a wrong one. On an action film the relationship is close to inverted — the loud passages are
/// gunfire and score and carry no subtitles, while the dialogue is quiet.
///
/// What separates speech in a FILM is not volume but placement. A cinema mix puts dialogue in the
/// CENTRE channel almost by definition, and spreads music and effects across the left, right and
/// surrounds. So the question each frame answers is not "how loud is this" but "how much of this is
/// coming from the centre" — weighted by loudness, because a whisper of centre over a whisper of
/// everything is dominance without being speech.
public enum VoiceActivity {

    /// Per-frame voice likelihood from the centre channel and the full mix.
    ///
    /// - Parameters:
    ///   - centre: RMS of the centre channel, already band-limited to the speech range.
    ///   - mix: RMS of every channel together, for the same frames.
    public static func score(centre: [Float], mix: [Float]) -> [Float] {
        let n = Swift.min(centre.count, mix.count)
        guard n > 0 else { return [] }
        var out = [Float]()
        out.reserveCapacity(n)
        for i in 0..<n {
            let c = Double(centre[i] < 0 ? 0 : centre[i])
            let raw = Double(mix[i])
            let m = raw < c ? c : raw                   // the mix contains the centre
            // Weighted by loudness, not dominance alone: a whisper of centre over a whisper of
            // everything is dominance without being speech. And because centre never exceeds the
            // mix, a source with no real centre — libvlc synthesises one as (L+R)/2 for stereo —
            // has dominance near 1 throughout, so this degrades to plain loudness rather than
            // collapsing to a constant that correlates with nothing.
            let dominance = c / (m + 1e-6)
            out.append(Float(c * dominance))
        }
        return out
    }
}

/// A band-pass over the speech range, applied sample by sample as the audio arrives.
///
/// Dialogue lives between roughly 300 Hz and 3.4 kHz — the band telephony was built around. Taking
/// everything else out of the centre channel before it is measured removes the two things most
/// likely to sit there and not be speech: the bass of a score, and the top end of effects.
///
/// Two one-pole sections rather than a designed biquad: the job is to bias a loudness measurement,
/// not to be transparent, and a one-pole pair has no stability or coefficient-precision questions
/// to get wrong in a callback that runs thousands of times a second.
public struct SpeechBandFilter: Sendable {
    // Two poles per edge. One is 6 dB per octave, which leaves a 50 Hz rumble at roughly a tenth of
    // the band's energy — not enough to stop a score's bass dominating the very measurement this
    // exists to clean up.
    private var low1: Float = 0
    private var low2: Float = 0
    private var bass1: Float = 0
    private var bass2: Float = 0
    private let lowAlpha: Float
    private let highAlpha: Float

    public init(sampleRate: Double, lowCutHz: Double = 300, highCutHz: Double = 3400) {
        lowAlpha = Self.alpha(cutoff: highCutHz, sampleRate: sampleRate)
        highAlpha = Self.alpha(cutoff: lowCutHz, sampleRate: sampleRate)
    }

    /// One sample in, one band-limited sample out.
    ///
    /// The high-pass is two SEPARATE one-pole differences, not one difference against a cascaded
    /// low-pass. Cascading first and subtracting once is not a two-pole high-pass at all: each pole
    /// adds phase lag, so the low-passed copy no longer lines up with the signal it is subtracted
    /// from, and the residual it leaves behind grows with every pole. Written that way a 50 Hz tone
    /// came through at a fifth of the band's energy — louder than the single-pole version it was
    /// meant to improve on.
    public mutating func process(_ sample: Float) -> Float {
        low1 += lowAlpha * (sample - low1)          // 2-pole low-pass: drop the top end
        low2 += lowAlpha * (low1 - low2)

        bass1 += highAlpha * (low2 - bass1)         // …then 2 one-pole high-passes: drop the bottom
        let once = low2 - bass1
        bass2 += highAlpha * (once - bass2)
        return once - bass2
    }

    /// One-pole smoothing coefficient for a cutoff, clamped so an absurd rate cannot make the
    /// filter unstable or a no-op.
    private static func alpha(cutoff: Double, sampleRate: Double) -> Float {
        guard sampleRate > 0 else { return 1 }
        let x = 2 * Double.pi * cutoff / sampleRate
        return Float(Swift.min(Swift.max(x / (x + 1), 0.0001), 0.9999))
    }
}
