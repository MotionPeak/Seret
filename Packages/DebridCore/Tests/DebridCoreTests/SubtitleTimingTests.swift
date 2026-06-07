import Testing
@testable import DebridCore

@Suite struct SubtitleTimingTests {
    @Test func parsesLastCueEndFromSRT() {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        Hello.

        2
        00:21:40,000 --> 00:21:44,250
        Goodbye.
        """
        let end = SubtitleTiming.lastCueEndSeconds(in: srt)
        #expect(end == 21 * 60 + 44.25)
    }

    @Test func parsesVTTDotMillisAndTakesMaxNotLast() {
        // WebVTT uses dots; and an out-of-order cue must not lower the max.
        let vtt = """
        WEBVTT

        00:40:00.000 --> 00:40:05.000
        Late line.

        00:05:00.000 --> 00:05:02.000
        Early line out of order.
        """
        #expect(SubtitleTiming.lastCueEndSeconds(in: vtt) == 2405.0)
    }

    @Test func returnsNilWhenNoCues() {
        #expect(SubtitleTiming.lastCueEndSeconds(in: "not a subtitle file") == nil)
        #expect(SubtitleTiming.lastCueEndSeconds(in: "") == nil)
    }
}
