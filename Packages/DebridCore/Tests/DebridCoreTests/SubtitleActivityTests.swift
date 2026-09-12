import Testing
import Foundation
@testable import DebridCore

/// Turning the two sides into the same shape, so `SubtitleSync` can correlate them.
@Suite struct SubtitleActivityTests {

    // MARK: - Cues → activity

    private let srt = """
    1
    00:00:02,000 --> 00:00:04,000
    First line

    2
    00:00:10,500 --> 00:00:12,000
    Second line
    """

    @Test func cueSpansAreReadWithBothStartAndEnd() {
        let spans = SubtitleTiming.cueSpans(in: srt)

        #expect(spans.count == 2)
        #expect(abs(spans[0].start - 2.0) < 0.001)
        #expect(abs(spans[0].end - 4.0) < 0.001)
        #expect(abs(spans[1].start - 10.5) < 0.001)
    }

    /// WebVTT spells its timestamps with a dot; a subtitle we cannot read is a subtitle we cannot
    /// sync.
    @Test func webVTTTimestampsAreReadToo() {
        let vtt = "WEBVTT\n\n00:00:01.250 --> 00:00:03.750\nHello"
        let spans = SubtitleTiming.cueSpans(in: vtt)

        #expect(spans.count == 1)
        #expect(abs(spans[0].start - 1.25) < 0.001)
        #expect(abs(spans[0].end - 3.75) < 0.001)
    }

    @Test func cuesBecomeAFrameVectorCoveringTheirSpan() {
        let v = SubtitleTiming.activity(in: srt, frameSeconds: 0.5, frames: 30)

        #expect(v.count == 30)
        #expect(v[3] == 0)          // 1.5–2.0s, before the first cue
        #expect(v[4] == 1)          // 2.0–2.5s, first cue
        #expect(v[7] == 1)          // 3.5–4.0s, still the first cue
        #expect(v[9] == 0)          // 4.5–5.0s, the gap
        #expect(v[21] == 1)         // 10.5–11.0s, second cue
    }

    /// A cue past the end of the window is simply not in it — an out-of-range write would trap.
    @Test func cuesBeyondTheWindowAreIgnored() {
        let v = SubtitleTiming.activity(in: srt, frameSeconds: 0.5, frames: 8)

        #expect(v.count == 8)
        #expect(v.contains(1))
    }

    // MARK: - Audio → activity

    /// Loudness alone is not speech: a film is mostly not silent. What separates dialogue from a
    /// score is that it stands ABOVE the local floor, so the threshold is taken from the material
    /// rather than fixed.
    @Test func loudFramesRelativeToTheMaterialCountAsSpeech() {
        var rms = [Float](repeating: 0.02, count: 100)      // quiet bed
        for i in 40..<50 { rms[i] = 0.5 }                    // dialogue

        let v = SpeechActivity.fromLoudness(rms)

        #expect(v.count == 100)
        #expect(v[45] == 1)
        #expect(v[10] == 0)
    }

    /// A uniformly loud passage carries no information — marking all of it as speech would let a
    /// music cue outvote the dialogue it is under.
    @Test func aUniformSignalYieldsNoActivity() {
        let v = SpeechActivity.fromLoudness([Float](repeating: 0.3, count: 50))

        #expect(v.allSatisfy { $0 == 0 })
    }

    @Test func anEmptySignalIsEmpty() {
        #expect(SpeechActivity.fromLoudness([]).isEmpty)
    }

    /// The whole point: a real subtitle, a matching speech signal built from the same cues shifted
    /// by a known amount, and the estimate recovers it end to end.
    @Test func aShiftedSubtitleIsMeasuredEndToEnd() {
        var cueText = ""
        for i in 0..<40 {                                    // a line every 15s, 3s long
            let start = Double(i) * 15 + 5
            cueText += "\(i + 1)\n\(stamp(start)) --> \(stamp(start + 3))\nLine \(i)\n\n"
        }
        let frames = 6000                                    // 600s at 0.1s
        let cues = SubtitleTiming.activity(in: cueText, frameSeconds: 0.1, frames: frames)
        // The audio has the same dialogue, 2.5s EARLIER than the subtitle claims.
        var speech = [Float](repeating: 0, count: frames)
        for i in 0..<frames where cues[min(frames - 1, i + 25)] == 1 { speech[i] = 1 }

        let result = SubtitleSync.estimate(speech: speech, cues: cues,
                                           frameSeconds: 0.1, maxLagSeconds: 15)

        #expect(result != nil)
        #expect(abs(result!.offsetSeconds - (-2.5)) < 0.2)   // show the lines 2.5s earlier
    }

    private func stamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60, s = Int(seconds) % 60
        let ms = Int((seconds - seconds.rounded(.down)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

/// The cue window has to line up with the audio window it is matched against.
@Suite struct SubtitleWindowTests {
    private let srt = """
    1
    00:05:02,000 --> 00:05:04,000
    Inside the window

    2
    00:00:10,000 --> 00:00:12,000
    Long before it
    """

    @Test func onlyCuesInsideTheWindowAppearAndAtTheRightPlace() {
        // A 60s window starting at 5 minutes, one frame per second.
        let v = SubtitleTiming.activity(in: srt, frameSeconds: 1, frames: 60, startSeconds: 300)

        #expect(v.count == 60)
        #expect(v[2] == 1)        // 302s — the first cue
        #expect(v[3] == 1)
        #expect(v[0] == 0)
        #expect(v[30] == 0)
        #expect(v.reduce(0, +) == 3)   // the 10s cue is far outside and must not appear
    }

    @Test func aWindowStartingAtZeroBehavesAsBefore() {
        let v = SubtitleTiming.activity(in: srt, frameSeconds: 1, frames: 20)
        #expect(v[10] == 1)       // the 10s cue
        #expect(v[2] == 0)
    }
}

/// Marking the loudest N frames, where N comes from what the subtitle claims.
@Suite struct SpeechDensityTests {

    @Test func theLoudestFractionIsMarked() {
        let frames: [Float] = (0..<100).map { Float($0) / 100 }      // a ramp
        let v = SpeechActivity.densest(frames, fraction: 0.25)

        #expect(v.filter { $0 == 1 }.count == 25)
        #expect(v[99] == 1)       // the loudest
        #expect(v[0] == 0)        // the quietest
    }

    /// The density it is asked for is the density it produces — that is the whole point, since the
    /// number comes from the subtitle it will be correlated against.
    @Test func theRequestedDensityIsHonoured() {
        let frames: [Float] = (0..<1000).map { Float(($0 * 7919) % 1000) / 1000 }
        for fraction in [0.1, 0.3, 0.64] {
            let count = SpeechActivity.densest(frames, fraction: fraction).filter { $0 == 1 }.count
            #expect(abs(Double(count) / 1000 - fraction) < 0.02, "fraction \(fraction)")
        }
    }

    @Test func aFlatSignalStillYieldsNothing() {
        #expect(SpeechActivity.densest([Float](repeating: 0.4, count: 50), fraction: 0.3)
            .allSatisfy { $0 == 0 })
    }

    @Test func emptyAndDegenerateFractionsAreSafe() {
        #expect(SpeechActivity.densest([], fraction: 0.5).isEmpty)
        #expect(SpeechActivity.densest([1, 2, 3], fraction: 0).count == 3)
        #expect(SpeechActivity.densest([1, 2, 3], fraction: 1).count == 3)
    }
}
