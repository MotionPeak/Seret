import Foundation

/// Measures how far a subtitle is out of step with the audio, by lining its cues up against where
/// speech actually happens.
///
/// Both sides are reduced to the same shape — one frame per `frameSeconds`, carrying 1 where
/// something is happening and 0 where it is not — so "how far out is it?" becomes "what shift makes
/// these two agree most", which is a cross-correlation. Same idea as ffsubsync; the difference is
/// the frame is coarse enough (100ms) that a direct search over the lag range costs a few tens of
/// millions of multiply-adds and needs no FFT, which keeps this pure Swift and Linux-portable.
///
/// The correlation is normalised (each window zero-meaned and scaled to unit norm) so the peak is a
/// number between -1 and 1 that means the same thing regardless of how talkative the film is, and
/// so a long stretch of silence cannot outscore a real match just by being large.
public enum SubtitleSync {

    public struct Estimate: Equatable, Sendable {
        /// Seconds to shift the subtitle by. Positive shows every line LATER — the same sign
        /// convention as `VideoPlayerEngine.setSubtitleDelay`, so it can be applied directly.
        public let offsetSeconds: Double
        /// How much better the winning shift was than the field, from 0 to 1. This is the guard
        /// against a confident lie: correlating two unrelated signals always has SOME maximum, and
        /// acting on it would drag a correct subtitle into nonsense.
        public let confidence: Double

        public init(offsetSeconds: Double, confidence: Double) {
            self.offsetSeconds = offsetSeconds
            self.confidence = confidence
        }
    }

    /// How much time one frame of either signal covers. 100ms places a cue closely enough to be
    /// imperceptible and keeps a direct correlation search over two minutes of lag down to a few
    /// tens of millions of multiply-adds.
    public static let frameSeconds = 0.1

    /// A peak must reach this to be believed at all.
    static let minimumPeak = 0.25
    /// …and must stand this far above the typical shift's score. A real alignment is a spike; noise
    /// is a plateau, and a plateau's maximum is meaningless.
    static let minimumProminence = 0.12
    /// Scores within this of the best are treated as indistinguishable, and the smallest shift
    /// among them wins. See the tie-break in `estimate`.
    static let tieTolerance = 0.02

    /// A measurement and the evidence behind it, including the ones that were not good enough.
    /// `estimate` is this with the unconvincing filtered out; having the numbers is what makes a
    /// refusal diagnosable instead of just silent.
    public struct Measurement: Equatable, Sendable {
        public let offsetSeconds: Double
        public let peak: Double
        public let background: Double
        public let confidence: Double
        public let accepted: Bool

        public var summary: String {
            String(format: "%+.2fs peak %.3f bg %.3f conf %.2f %@",
                   offsetSeconds, peak, background, confidence, accepted ? "OK" : "REJECTED")
        }
    }

    /// The shift that best lines `cues` up with `speech`, or nil when nothing convincing was found.
    ///
    /// - Parameters:
    ///   - speech: activity per frame from the audio (1 = something is being said).
    ///   - cues: activity per frame from the subtitle (1 = a line is on screen).
    ///   - frameSeconds: how much time one frame covers, for both vectors.
    ///   - maxLagSeconds: how far out the subtitle is allowed to be. Searching wider costs time and
    ///     invites a spurious match, so this is a real limit rather than a formality.
    public static func estimate(speech: [Float], cues: [Float],
                                frameSeconds: Double, maxLagSeconds: Double) -> Estimate? {
        guard let m = measure(speech: speech, cues: cues, frameSeconds: frameSeconds,
                              maxLagSeconds: maxLagSeconds), m.accepted else { return nil }
        return Estimate(offsetSeconds: m.offsetSeconds, confidence: m.confidence)
    }

    /// How far apart the two halves' answers may be and still count as the same answer.
    public static let agreementSeconds = 1.5
    /// The least a half may be and still be asked to corroborate anything.
    public static let minimumHalfSeconds = 45.0
    /// How well the whole window's answer must still score on each half. Lower than the bar for a
    /// peak found from scratch: a half has half the dialogue to match, so it is asked only whether
    /// the alignment is really present, not whether it could have discovered it alone.
    public static let corroborationFloor = 0.15

    /// An estimate that has proved itself on both halves of the window, or nil.
    ///
    /// One window is not enough to believe. With everything else working, a window a minute into a
    /// film measured the offset exactly while a window twenty-four minutes into the SAME film with
    /// the SAME subtitle confidently measured +87 seconds. A constant offset cannot be both, so one
    /// of them was a spurious peak that a dialogue-dense stretch happened to support — and nothing
    /// in a single measurement distinguishes the two.
    ///
    /// Splitting costs no extra audio: it is the same frames, measured again in halves. A real
    /// alignment is present in both; a peak that exists only because one stretch resembles itself
    /// at some shift does not survive being cut in two.
    /// - Parameter minimumHalfSeconds: the least a half may be and still be asked to corroborate.
    ///   Injectable so a test can exercise the wiring on a few seconds of signal — the correlation
    ///   itself is covered by this type's own suites, and running realistic windows in the player
    ///   tests starved every sleep-based test sharing the machine.
    public static func corroboratedEstimate(speech: [Float], cues: [Float],
                                            frameSeconds: Double,
                                            maxLagSeconds: Double,
                                            minimumHalfSeconds: Double = SubtitleSync.minimumHalfSeconds) -> Estimate? {
        guard let whole = measure(speech: speech, cues: cues, frameSeconds: frameSeconds,
                                  maxLagSeconds: maxLagSeconds), whole.accepted else { return nil }
        // Each half has to be a real measurement in its own right. The bar is its DURATION, not a
        // multiple of the lag range: `correlation` already refuses a shift that leaves too little
        // overlapping, so a wide search over a short half costs nothing but finds nothing either.
        let half = Swift.min(speech.count, cues.count) / 2
        guard Double(half) * frameSeconds >= minimumHalfSeconds else { return nil }

        // Ask each half whether the WHOLE's answer holds there — not what it would conclude on its
        // own. Re-searching a half freely invites the same sliver-overlap false peak that made this
        // guard necessary; checking one lag cannot.
        let lag = Int((whole.offsetSeconds / frameSeconds).rounded())
        for range in [0..<half, half..<Swift.min(speech.count, cues.count)] {
            let score = correlation(speech: Array(speech[range]), cues: Array(cues[range]), lag: lag)
            guard score >= corroborationFloor else { return nil }
        }
        return Estimate(offsetSeconds: whole.offsetSeconds, confidence: whole.confidence)
    }

    /// The same search, reporting what it found whether or not it passed the gates.
    public static func measure(speech: [Float], cues: [Float],
                               frameSeconds: Double, maxLagSeconds: Double) -> Measurement? {
        guard !speech.isEmpty, !cues.isEmpty, frameSeconds > 0, maxLagSeconds > 0 else { return nil }
        // A cue track with no cues, or audio with no quiet in it, carries no information: there is
        // nothing to line up, and every shift scores identically.
        guard varies(speech), varies(cues) else { return nil }

        // A shift can only be searched as far as the window can still overlap itself meaningfully.
        // Asked for ±120s over a 219-second window, the search reached lags leaving barely half of
        // it overlapping and found a confident +87s there — while both halves of the same audio
        // said +0.1s, which was the truth. Capping the range at a quarter of the window keeps every
        // lag above 75% overlap and removes that class of answer entirely.
        let windowSeconds = Double(Swift.min(speech.count, cues.count)) * frameSeconds
        let searchable = Swift.min(maxLagSeconds, windowSeconds * 0.25)
        let maxLag = Int((searchable / frameSeconds).rounded())
        guard maxLag > 0 else { return nil }

        var scores: [Double] = []
        scores.reserveCapacity(2 * maxLag + 1)
        for lag in -maxLag...maxLag {
            scores.append(correlation(speech: speech, cues: cues, lag: lag))
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }
        let peak = scores[best]

        // Among shifts that explain the audio equally well, take the SMALLEST correction.
        //
        // Dialogue is rhythmic, so correlation is too: a subtitle whose lines fall at a steady
        // pace scores just as well shifted by one whole line as by none, and there is no evidence
        // in the signal to separate them. Picking the numerical maximum then lands wherever
        // rounding fell — in testing, reliably at the far edge of the search window. When the data
        // cannot distinguish two answers, the one that moves the subtitle least is the one to give.
        // …but only between DISTINCT explanations, which is why a candidate has to be a local
        // maximum. A single peak is broad — cues are seconds long, so the lags either side of the
        // true answer score almost as well — and without this the rule slides down that shoulder
        // and reports a correction half a second short of the right one.
        let peakIndex = scores.indices
            .filter { scores[$0] >= peak - tieTolerance && isLocalMaximum(scores, $0) }
            .min { abs($0 - maxLag) < abs($1 - maxLag) } ?? best

        // Prominence against the field, ignoring the neighbourhood of the peak itself — the frames
        // either side of a true match correlate well too, and counting them as "the field" would
        // make every correct answer look unremarkable.
        let guardBand = max(1, Int(1.0 / frameSeconds))         // ±1s around the peak
        let others = scores.indices
            .filter { abs($0 - peakIndex) > guardBand }
            .map { scores[$0] }
        guard !others.isEmpty else { return nil }
        let background = others.reduce(0, +) / Double(others.count)
        let chosen = scores[peakIndex]

        // `correlation` pairs `speech[i]` with `cues[i - lag]`, so the winning lag says the cue that
        // belongs with the speech at `i` is sitting at `i - lag`: a POSITIVE lag means the cues run
        // EARLY and have to be pushed later, which is the same sign the correction takes.
        let lag = peakIndex - maxLag
        let confidence = min(1, max(0, chosen - background) / max(chosen, 0.0001))
        return Measurement(offsetSeconds: Double(lag) * frameSeconds,
                           peak: chosen, background: background, confidence: confidence,
                           accepted: chosen >= minimumPeak && chosen - background >= minimumProminence)
    }

    /// Normalised cross-correlation of the two vectors at one shift, over the frames they share.
    ///
    /// `lag > 0` means the cues run EARLIER than the speech. Only the overlapping region is scored,
    /// and each side is zero-meaned within that region — otherwise a shift that happens to align
    /// two long runs of silence would win on sheer quantity of agreement about nothing.
    public static func correlation(speech: [Float], cues: [Float], lag: Int) -> Double {
        let start = max(0, lag)
        let end = min(speech.count, cues.count + lag)
        // HALF the shorter signal, at least. Eight frames was "not literally zero", and a quarter
        // was still too generous: measured on a real film, a 120-second half produced a confident
        // 0.435 peak at a lag that left only a third of it overlapping — a sliver long enough to
        // agree by chance and short enough to mean nothing.
        let shorter = Swift.min(speech.count, cues.count)
        guard end - start >= Swift.max(8, shorter / 2) else { return 0 }

        // Unsafe buffers, deliberately. This is the innermost loop of the whole measurement — a
        // production window is a few thousand frames searched over a few thousand shifts, run four
        // times — and bounds-checked subscripting dominated it. In the unit suite it was slow
        // enough to starve every sleep-based test sharing the machine.
        return speech.withUnsafeBufferPointer { a in
            cues.withUnsafeBufferPointer { b in
                var sumA = 0.0, sumB = 0.0
                for i in start..<end {
                    sumA += Double(a[i])
                    sumB += Double(b[i - lag])
                }
                let n = Double(end - start)
                let meanA = sumA / n, meanB = sumB / n

                var dot = 0.0, normA = 0.0, normB = 0.0
                for i in start..<end {
                    let x = Double(a[i]) - meanA
                    let y = Double(b[i - lag]) - meanB
                    dot += x * y
                    normA += x * x
                    normB += y * y
                }
                guard normA > 0, normB > 0 else { return 0 }
                return dot / (normA * normB).squareRoot()
            }
        }
    }

    /// Whether `i` is at least as high as both its neighbours — a peak in its own right rather
    /// than a point on the side of someone else's.
    private static func isLocalMaximum(_ scores: [Double], _ i: Int) -> Bool {
        let left = i > 0 ? scores[i - 1] : -.infinity
        let right = i < scores.count - 1 ? scores[i + 1] : -.infinity
        return scores[i] >= left && scores[i] >= right
    }

    /// Whether a vector carries any information at all — an all-0 or all-1 signal correlates with
    /// everything equally and so with nothing usefully.
    private static func varies(_ v: [Float]) -> Bool {
        guard let first = v.first else { return false }
        return v.contains { $0 != first }
    }
}
