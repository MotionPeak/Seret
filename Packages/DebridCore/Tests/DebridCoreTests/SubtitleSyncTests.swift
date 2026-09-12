import Testing
import Foundation
@testable import DebridCore

/// Finding how far a subtitle is out, by lining its cues up against where the speech actually is.
///
/// The two signals are sampled the same way — one frame per `frameSeconds`, 1 where something is
/// happening and 0 where it is not — so the question becomes "what shift makes these two agree
/// most", which is a cross-correlation. This is the same shape as ffsubsync, at a coarse enough
/// frame that a direct search over the lag range is cheap and no FFT is needed.
@Suite struct SubtitleSyncTests {

    /// An activity vector with 1s over the given frame ranges.
    private func activity(_ length: Int, _ spans: [(Int, Int)]) -> [Float] {
        var v = [Float](repeating: 0, count: length)
        for (start, end) in spans { for i in start..<end where i < length { v[i] = 1 } }
        return v
    }

    /// The subtitle is late by a known amount; the estimate has to be that amount, negated —
    /// the correction shows every line EARLIER.
    @Test func aConstantOffsetIsRecovered() {
        let speech = activity(600, [(50, 70), (120, 140), (300, 330), (450, 480)])
        let shift = 40                                   // cues sit 40 frames after the speech
        let cues = activity(600, [(90, 110), (160, 180), (340, 370), (490, 520)])

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds - Double(-shift) * 0.1) < 0.05)
    }

    /// The other direction — a subtitle running EARLY has to be pushed later.
    @Test func anEarlySubtitleGetsAPositiveOffset() {
        let speech = activity(600, [(100, 120), (250, 280), (400, 430)])
        let cues = activity(600, [(70, 90), (220, 250), (370, 400)])

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds - 3.0) < 0.05)     // 30 frames × 0.1s, later
    }

    /// An already-aligned subtitle must come back as zero, not be nudged by noise.
    @Test func anAlignedSubtitleNeedsNoCorrection() {
        let spans = [(40, 60), (150, 175), (300, 340), (500, 520)]
        let result = SubtitleSync.estimate(speech: activity(600, spans), cues: activity(600, spans),
                                           frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds) < 0.05)
        #expect(result!.confidence > 0.9)
    }

    /// A shift beyond the search window must be reported as not found rather than as the best
    /// wrong answer inside it — a confident lie is worse than "I couldn't tell".
    @Test func aShiftBeyondTheSearchWindowIsNotGuessedAt() {
        let speech = activity(900, [(50, 70), (200, 230), (400, 430)])
        let cues = activity(900, [(650, 670), (800, 830)])     // far outside ±3s

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 3)

        #expect(result == nil)
    }

    /// Two signals with nothing in common must not produce an answer. Correlating noise always has
    /// SOME maximum; reporting it would shift a correct subtitle into nonsense.
    @Test func unrelatedSignalsAreRejected() {
        // Seeded, so a failure here is reproducible rather than a coin toss in CI.
        var seed: UInt64 = 0x5EED
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24)
        }
        let speech: [Float] = (0..<2000).map { _ in next() < 0.2 ? 1 : 0 }
        let cues: [Float] = (0..<2000).map { _ in next() < 0.2 ? 1 : 0 }

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 30)

        #expect(result == nil)
    }

    /// Real speech is not only dialogue — music and effects light up frames no cue covers. The
    /// estimate has to survive that, because it is the normal case rather than the exception.
    @Test func extraSpeechFramesDoNotBreakTheEstimate() {
        var speech = activity(1200, [(100, 130), (300, 340), (600, 650), (900, 940)])
        for i in stride(from: 0, to: 1200, by: 37) { speech[i] = 1 }   // scattered non-dialogue
        let cues = activity(1200, [(120, 150), (320, 360), (620, 670), (920, 960)])

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds - (-2.0)) < 0.15)
    }

    /// Empty input is a question with no answer, not a crash and not a zero.
    @Test func emptyInputYieldsNothing() {
        #expect(SubtitleSync.estimate(speech: [], cues: [1, 0, 1],
                                      frameSeconds: 0.1, maxLagSeconds: 5) == nil)
        #expect(SubtitleSync.estimate(speech: [1, 0, 1], cues: [],
                                      frameSeconds: 0.1, maxLagSeconds: 5) == nil)
        // A cue track with no cues at all carries no information to align with.
        #expect(SubtitleSync.estimate(speech: [1, 0, 1, 1], cues: [0, 0, 0, 0],
                                      frameSeconds: 0.1, maxLagSeconds: 5) == nil)
    }
}
