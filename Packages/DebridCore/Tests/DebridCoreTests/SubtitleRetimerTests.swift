import Testing
@testable import DebridCore

@Suite struct SubtitleRetimerTests {

    // MARK: - factor

    @Test func factorIsSubtitleRateOverVideoRate() {
        // The canonical case: every OpenSubtitles entry for a BBC show is timed against the 25fps
        // PAL master, and the file playing is a 23.976 encode. The 23.976 version runs LONGER for
        // the same content, so the cues must be stretched — a factor above 1.
        let f = try! #require(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 23.976))
        #expect(abs(f - 1.042709) < 0.000_01)
    }

    @Test func noFactorWhenTheRatesAgree() {
        #expect(SubtitleRetimer.factor(subtitleFPS: 23.976, videoFPS: 23.976) == nil)
        // 24 vs 23.976 is a real pair, but a 0.1% correction is a millisecond an hour. Not worth
        // rewriting a file the viewer would never see a difference in.
        #expect(SubtitleRetimer.factor(subtitleFPS: 24, videoFPS: 23.976) == nil)
    }

    @Test func noFactorWithoutBothRates() {
        #expect(SubtitleRetimer.factor(subtitleFPS: nil, videoFPS: 23.976) == nil)
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: nil) == nil)
        // OpenSubtitles returns 0.0 for "unknown", which must not be read as a real rate.
        #expect(SubtitleRetimer.factor(subtitleFPS: 0, videoFPS: 23.976) == nil)
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 0) == nil)
    }

    @Test func noFactorForARatioNoRealPairProduces() {
        // Every real mismatch lives inside ±5%. Anything wilder is bad metadata, and acting on it
        // would destroy a subtitle that may well have been fine.
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 12) == nil)
        #expect(SubtitleRetimer.factor(subtitleFPS: 10, videoFPS: 23.976) == nil)
    }

    @Test func refusesToStretchCuesPastTheRuntime() {
        // A correction that pushes dialogue beyond the end of the file is self-evidently wrong,
        // whatever the declared rates say. 5000s of cues in a 5100s file cannot take a 4% stretch.
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 23.976,
                                       lastCueEnd: 5000, duration: 5100) == nil)
        // …but the same stretch inside a long enough file is exactly what we want to apply.
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 23.976,
                                       lastCueEnd: 5000, duration: 5400) != nil)
    }

    @Test func aRuntimeItAlreadyFitsIsLeftAlone() {
        // The declared rate is uploader-supplied and sometimes simply wrong. When the cues already
        // span the file's runtime the subtitle is in sync with THIS cut, so believe the evidence
        // over the metadata and change nothing.
        #expect(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 23.976,
                                       lastCueEnd: 5240, duration: 5286) == nil)
    }

    // MARK: - rescale

    @Test func rescaleStretchesBothEndsOfEveryCue() {
        let srt = """
        1
        00:00:10,000 --> 00:00:12,500
        First line.

        2
        00:59:00,000 --> 00:59:01,000
        After the hour.
        """
        let out = SubtitleRetimer.rescale(srt, by: 2)
        #expect(out.contains("00:00:20,000 --> 00:00:25,000"))
        #expect(out.contains("01:58:00,000 --> 01:58:02,000"))
    }

    @Test func rescaleLeavesEverythingThatIsNotACueTimestampAlone() {
        let srt = """
        1
        00:00:10,000 --> 00:00:12,000
        Meet me at 10,000 feet in 3 hours.
        """
        let out = SubtitleRetimer.rescale(srt, by: 2)
        // The cue index and the dialogue — including numbers that look like timings — survive.
        #expect(out.contains("Meet me at 10,000 feet in 3 hours."))
        #expect(out.hasPrefix("1\n"))
        #expect(out.contains("00:00:20,000 --> 00:00:24,000"))
    }

    @Test func rescaleKeepsWebVTTDotsAndCueSettings() {
        let vtt = """
        WEBVTT

        00:00:10.000 --> 00:00:12.000 line:90% align:middle
        A line.
        """
        let out = SubtitleRetimer.rescale(vtt, by: 2)
        #expect(out.contains("00:00:20.000 --> 00:00:24.000 line:90% align:middle"))
        #expect(out.hasPrefix("WEBVTT"))
    }

    @Test func rescaleNormalisesAnHourlessWebVTTStamp() {
        // WebVTT permits MM:SS.mmm. Emitting the full HH:MM:SS.mmm form is valid in both formats.
        let vtt = "00:10.000 --> 00:12.000\nA line."
        #expect(SubtitleRetimer.rescale(vtt, by: 2).contains("00:00:20.000 --> 00:00:24.000"))
    }

    @Test func theRealCorrectionRecoversTheDriftTheViewerSees() {
        // The bug, measured: a cue an hour into a 25fps-timed file lands 2m33s early against a
        // 23.976 encode — which is why lines start getting clipped by their successors partway in.
        let f = try! #require(SubtitleRetimer.factor(subtitleFPS: 25, videoFPS: 23.976))
        let out = SubtitleRetimer.rescale("01:00:00,000 --> 01:00:02,000\nLine.", by: f)
        #expect(out.contains("01:02:33,7"))
    }

    @Test func rescalingByOneChangesNothing() {
        let srt = "1\n00:00:10,000 --> 00:00:12,000\nLine."
        #expect(SubtitleRetimer.rescale(srt, by: 1) == srt)
    }

    // MARK: - shift

    @Test func shiftMovesBothEndsOfEveryCueByTheSameAmount() {
        // The case that made subtitles vanish: a line 11.5s late, pulled earlier. libvlc drops a
        // line asked to appear more than a few seconds before it has read it, so the offset has
        // to be in the file itself.
        let srt = """
        1
        00:00:20,000 --> 00:00:22,500
        First line.

        2
        01:00:00,000 --> 01:00:01,000
        After the hour.
        """
        let out = SubtitleRetimer.shift(srt, by: -11.5)
        #expect(out.contains("00:00:08,500 --> 00:00:11,000"))
        #expect(out.contains("00:59:48,500 --> 00:59:49,500"))
        #expect(out.contains("First line.") && out.hasPrefix("1\n"))
    }

    @Test func aPositiveShiftShowsEveryLineLater() {
        let out = SubtitleRetimer.shift("00:00:10,000 --> 00:00:12,000\nLine.", by: 2.25)
        #expect(out.contains("00:00:12,250 --> 00:00:14,250"))
    }

    @Test func aCueShiftedPastTheStartIsClampedToZeroNeverNegative() {
        // A timestamp cannot be negative. A line wholly before zero collapses to an empty cue that
        // is never shown; one straddling zero keeps the part that is still on the timeline.
        let srt = """
        00:00:05,000 --> 00:00:07,000
        Gone.

        00:00:08,000 --> 00:00:12,000
        Partly kept.
        """
        let out = SubtitleRetimer.shift(srt, by: -10)
        #expect(out.contains("00:00:00,000 --> 00:00:00,000\nGone."))
        #expect(out.contains("00:00:00,000 --> 00:00:02,000\nPartly kept."))
    }

    @Test func shiftKeepsWebVTTDotsAndCueSettings() {
        let vtt = "WEBVTT\n\n00:00:10.000 --> 00:00:12.000 line:90%\nA line."
        #expect(SubtitleRetimer.shift(vtt, by: -1)
            .contains("00:00:09.000 --> 00:00:11.000 line:90%"))
    }

    @Test func shiftingByZeroChangesNothing() {
        let srt = "1\n00:00:10,000 --> 00:00:12,000\nLine."
        #expect(SubtitleRetimer.shift(srt, by: 0) == srt)
    }
}
