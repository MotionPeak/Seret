import DebridCore
import Testing
@testable import DebridUI

/// Which Hebrew mark a version or a title gets. A Hebrew track inside the file is timed to that
/// exact cut, so it earns its own mark; a subtitle OpenSubtitles made for the release keeps the
/// Matched pill.
@Suite struct HebrewIndicatorTests {
    @Test func bothInFileKindsGetTheInFileMark() {
        // A file whose only Hebrew is a picture (PGS) track is just as in sync as a text one.
        #expect(HebrewIndicator(HebrewSubtitles.builtIn) == .inFile)
        #expect(HebrewIndicator(HebrewSubtitles.builtInImage) == .inFile)
    }

    @Test func aMatchedSubtitleKeepsThePill() {
        #expect(HebrewIndicator(HebrewSubtitles.matched) == .matched)
    }

    @Test func aVersionWithNothingKnownGetsNoMark() {
        #expect(HebrewIndicator(HebrewSubtitles.none) == nil)
    }

    @Test func theTitleChipUsesTheSameMarks() {
        // The hero and the rows must never disagree about what "in the file" looks like.
        #expect(HebrewIndicator(chip: .builtIn) == .inFile)
        #expect(HebrewIndicator(chip: .matched) == .matched)
        #expect(HebrewIndicator(chip: .available) == .available)
    }

    @Test func onlyTheInFileMarkPromisesSync() {
        #expect(HebrewIndicator.inFile.detail != nil)
        #expect(HebrewIndicator.matched.detail == nil)
        #expect(HebrewIndicator.available.detail == nil)
    }
}
