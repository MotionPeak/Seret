import Testing
import Foundation
@testable import DebridCore

/// Reading a subtitle's LINES, not just its timings.
///
/// `SubtitleTiming` only ever needed the timestamps — Up Next keys off the last cue's end, and
/// auto-sync correlates a 0/1 activity signal. Showing the viewer a line to press against needs
/// the text, and needs it to survive the encodings and dialects these files actually arrive in.
@Suite struct SubtitleCuesTests {

    @Test func parsesSRTIndexTimesAndText() {
        let srt = """
        1
        00:00:05,000 --> 00:00:07,500
        Hello there.

        2
        00:01:02,250 --> 00:01:04,000
        General Kenobi.

        """
        let cues = SubtitleCues.parse(srt)

        #expect(cues.count == 2)
        #expect(cues[0].id == 0)
        #expect(cues[0].start == 5.0)
        #expect(cues[0].end == 7.5)
        #expect(cues[0].text == "Hello there.")
        #expect(cues[1].id == 1)
        #expect(cues[1].start == 62.25)
        #expect(cues[1].text == "General Kenobi.")
    }

    @Test func parsesVTTDotTimestampsAndIgnoresItsHeader() {
        let vtt = """
        WEBVTT

        00:00:09.100 --> 00:00:11.000
        A dot, not a comma.

        """
        let cues = SubtitleCues.parse(vtt)

        #expect(cues.count == 1)
        #expect(cues[0].start == 9.1)
        #expect(cues[0].text == "A dot, not a comma.")
    }

    @Test func toleratesCRLFAndALeadingBOM() {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows wrote this.\r\n\r\n"
        let cues = SubtitleCues.parse(srt)

        #expect(cues.count == 1)
        #expect(cues[0].text == "Windows wrote this.")
    }

    @Test func joinsMultiLineCuesAndStripsMarkup() {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        <i>First half</i>
        {\\an8}second half

        """
        let cues = SubtitleCues.parse(srt)

        #expect(cues.count == 1)
        #expect(cues[0].text == "First half second half")
    }

    /// Cues are not guaranteed to be in order in the file, and the panel indexes into the list by
    /// position — so the list must be sorted and the ids must match the sorted order.
    @Test func sortsCuesAndNumbersThemInTimeOrder() {
        let srt = """
        1
        00:00:30,000 --> 00:00:31,000
        Later.

        2
        00:00:10,000 --> 00:00:11,000
        Earlier.

        """
        let cues = SubtitleCues.parse(srt)

        #expect(cues.map(\.text) == ["Earlier.", "Later."])
        #expect(cues.map(\.id) == [0, 1])
    }

    /// A file that never blank-lines between cues still parses. `SubtitleTiming.cueSpans` is
    /// re-expressed on this parser in Task 2, and it found timing lines by regex regardless of
    /// block structure — losing that would silently degrade auto-sync.
    @Test func parsesCuesThatAreNotSeparatedByBlankLines() {
        let srt = """
        1
        00:00:05,000 --> 00:00:06,000
        One.
        2
        00:00:07,000 --> 00:00:08,000
        Two.
        """
        let cues = SubtitleCues.parse(srt)

        #expect(cues.count == 2)
        #expect(cues[0].text == "One.")
        #expect(cues[1].text == "Two.")
    }

    @Test func skipsCuesWhoseEndDoesNotFollowTheirStart() {
        let srt = """
        1
        00:00:09,000 --> 00:00:05,000
        Backwards.

        2
        00:00:10,000 --> 00:00:12,000
        Fine.

        """
        #expect(SubtitleCues.parse(srt).map(\.text) == ["Fine."])
    }

    @Test func nearestPrefersTheCueOnScreen() {
        let cues = [SubtitleCue(id: 0, start: 10, end: 12, text: "a"),
                    SubtitleCue(id: 1, start: 20, end: 22, text: "b")]
        #expect(SubtitleCues.nearest(to: 11, in: cues) == 0)
    }

    @Test func nearestFallsBackToTheClosestStartInAGap() {
        let cues = [SubtitleCue(id: 0, start: 10, end: 12, text: "a"),
                    SubtitleCue(id: 1, start: 20, end: 22, text: "b")]
        #expect(SubtitleCues.nearest(to: 18, in: cues) == 1)
        #expect(SubtitleCues.nearest(to: 13, in: cues) == 0)
        #expect(SubtitleCues.nearest(to: 5, in: []) == nil)
    }

    /// `cueSpans` and `parse` must see the same cues — they are the same parse, and auto-sync
    /// correlates against one while the panel indexes the other.
    @Test func cueSpansAgreesWithTheParser() {
        let srt = """
        1
        00:00:05,000 --> 00:00:07,500
        Hello there.

        2
        00:01:02,250 --> 00:01:04,000
        General Kenobi.

        """
        let spans = SubtitleTiming.cueSpans(in: srt)
        let cues = SubtitleCues.parse(srt)

        #expect(spans.count == cues.count)
        #expect(spans.map(\.start) == cues.map(\.start))
        #expect(spans.map(\.end) == cues.map(\.end))
    }

    @Test func sliceClampsAtBothEnds() {
        let cues = (0..<5).map { SubtitleCue(id: $0, start: Double($0), end: Double($0) + 0.5,
                                             text: "\($0)") }
        #expect(SubtitleCues.slice(around: 0, radius: 2, in: cues).map(\.id) == [0, 1, 2])
        #expect(SubtitleCues.slice(around: 4, radius: 2, in: cues).map(\.id) == [2, 3, 4])
        #expect(SubtitleCues.slice(around: 2, radius: 1, in: cues).map(\.id) == [1, 2, 3])
        #expect(SubtitleCues.slice(around: 9, radius: 1, in: cues).isEmpty)
    }
}
