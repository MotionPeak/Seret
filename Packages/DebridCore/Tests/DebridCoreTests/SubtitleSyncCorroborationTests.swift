import Testing
import Foundation
@testable import DebridCore

/// One window is not enough to believe.
///
/// With the centre channel finally read correctly, a window a minute into a film measured the
/// offset exactly — and a window twenty-four minutes into the SAME film, with the SAME subtitle,
/// confidently measured +87 seconds. A constant offset cannot be both, so at least one was a
/// spurious peak that a dialogue-dense stretch happened to support.
///
/// The cheap guard is to make the answer prove itself on halves of the audio already collected: a
/// real alignment holds in the first half and the second, while a peak that only exists because a
/// particular stretch is self-similar does not survive being split.
@Suite struct SubtitleSyncCorroborationTests {

    /// Speech and cues that agree at a known shift, over `frames` frames.
    private func signals(shiftFrames: Int, frames: Int, period: Int = 40)
    -> (speech: [Float], cues: [Float]) {
        var speech = [Float](repeating: 0, count: frames)
        var cues = [Float](repeating: 0, count: frames)
        var seed: UInt64 = 7
        var t = 10
        while t < frames - 40 {
            for i in t..<min(t + 12, frames) { speech[i] = 1 }
            for i in (t + shiftFrames)..<min(t + shiftFrames + 12, frames) where i >= 0 {
                cues[i] = 1
            }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            t += 20 + Int(seed >> 52) % period
        }
        return (speech, cues)
    }

    @Test func anOffsetThatHoldsInBothHalvesIsAccepted() {
        let s = signals(shiftFrames: 30, frames: 2400)

        let result = SubtitleSync.corroboratedEstimate(
            speech: s.speech, cues: s.cues, frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds - (-3.0)) < 0.25)
    }

    /// The case this exists for: the two halves disagree, so the window's confident answer is not
    /// to be trusted and nothing is applied.
    @Test func halvesThatDisagreeAreRefused() {
        let first = signals(shiftFrames: 20, frames: 1200)
        let second = signals(shiftFrames: -50, frames: 1200)
        let speech = first.speech + second.speech
        let cues = first.cues + second.cues

        let result = SubtitleSync.corroboratedEstimate(
            speech: speech, cues: cues, frameSeconds: 0.1, maxLagSeconds: 12)

        #expect(result == nil)
    }

    /// A window too short to split cannot corroborate anything, and must say so rather than
    /// quietly falling back to the unchecked answer.
    @Test func aWindowTooShortToSplitIsRefused() {
        let s = signals(shiftFrames: 10, frames: 120)

        #expect(SubtitleSync.corroboratedEstimate(
            speech: s.speech, cues: s.cues, frameSeconds: 0.1, maxLagSeconds: 12) == nil)
    }

    /// Noise is refused here as it is by the plain estimate — the split is an extra gate, never a
    /// way past the existing ones.
    @Test func noiseIsStillRefused() {
        var seed: UInt64 = 3
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) < 0.25 ? 1 : 0
        }
        let speech = (0..<2400).map { _ in next() }
        let cues = (0..<2400).map { _ in next() }

        #expect(SubtitleSync.corroboratedEstimate(
            speech: speech, cues: cues, frameSeconds: 0.1, maxLagSeconds: 12) == nil)
    }
}
