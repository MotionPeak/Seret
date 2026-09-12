import Testing
import Foundation
@testable import DebridCore

/// `Sherlock.S01E00.1080p.Bluray.x265-HiQVE.mkv` — read off the real library — was parsed as
/// episode ZERO of series 1, which is what it literally says and not what it means.
///
/// `SxxE00` is the scene convention for a SPECIAL: the extra that accompanies season xx, not an
/// episode of it. Filed as S1E0 it did three things wrong. It sorted ahead of the premiere, so Play,
/// resume and the auto-advance all landed on the unaired pilot instead of "A Study in Pink". TMDB
/// has no episode 0 of series 1, so it drew as a nameless card. And the subtitle search asked
/// OpenSubtitles for `episode_number=0`, which cannot match anything.
///
/// Season 0 is what every media server and TMDB itself call Specials — verified against TMDB for
/// this exact show: `tv/19885/season/0` is named "Specials" and its **E1 is "Unaired Pilot"**.
@Suite struct SpecialEpisodeParsingTests {

    private let parser = FilenameParser()

    @Test func aZeroEpisodeIsASpecialNotEpisodeZero() {
        let p = parser.parse("Sherlock.S01E00.1080p.Bluray.x265-HiQVE.mkv")

        #expect(p.season == 0)          // Specials
        #expect(p.episode == 1)         // the special accompanying series 1
        #expect(p.title == "Sherlock")
    }

    /// The number carries the season it belongs to, which is the only thing the name actually says
    /// — and is what keeps two specials from colliding on one key. Getting that wrong merged them
    /// into a single episode row holding two different files.
    @Test func specialsFromDifferentSeasonsDoNotCollide() {
        let first = parser.parse("Show.S01E00.1080p.WEB-DL.x264-GRP.mkv")
        let second = parser.parse("Show.S02E00.1080p.WEB-DL.x264-GRP.mkv")

        #expect(first.season == 0)
        #expect(second.season == 0)
        #expect(first.episode != second.episode)
        #expect(first.episode == 1)
        #expect(second.episode == 2)
    }

    /// A file that is ALREADY stated as a special keeps exactly what it says — `S00E03` is the
    /// third special, and nothing here may renumber it.
    @Test func anExplicitSpecialIsLeftAlone() {
        let p = parser.parse("Show.S00E03.1080p.WEB-DL.x264-GRP.mkv")

        #expect(p.season == 0)
        #expect(p.episode == 3)
    }

    /// Everything that is a real episode must be untouched — this rule fires on E00 only.
    @Test func ordinaryEpisodesAreUnaffected() {
        for (name, season, episode) in [
            ("Sherlock.S01E01.1080p.Bluray.x265-HiQVE.mkv", 1, 1),
            ("Sherlock.S04E03.1080p.Bluray.x265-HiQVE.mkv", 4, 3),
            ("Show.S01E10.720p.HDTV.x264.mkv", 1, 10),
            ("Show.1x00.720p.HDTV.x264.mkv", 0, 1),        // the `NxM` spelling of the same thing
        ] {
            let p = parser.parse(name)
            #expect(p.season == season, "\(name)")
            #expect(p.episode == episode, "\(name)")
        }
    }

    /// A season pack is still a pack — no episode number means no special either.
    @Test func aSeasonPackIsNotTurnedIntoASpecial() {
        let p = parser.parse("Sherlock.S01.1080p.Bluray.x265-HiQVE")

        #expect(p.season == 1)
        #expect(p.episode == nil)
    }
}
