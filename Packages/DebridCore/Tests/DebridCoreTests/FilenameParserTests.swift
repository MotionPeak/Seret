import Testing
@testable import DebridCore

struct FilenameParserTests {
    let parser = FilenameParser()

    @Test func parsesA4KBluRayMovie() {
        let r = parser.parse("Dune.Part.Two.2024.2160p.UHD.BluRay.x265-WiKi.mkv")
        #expect(r.title == "Dune Part Two")
        #expect(r.year == 2024)
        #expect(r.resolution == "2160p")
        #expect(r.source == "BluRay")
        #expect(r.videoCodec == "x265")
        #expect(r.releaseGroup == "WiKi")
        #expect(r.season == nil)
        #expect(r.episode == nil)
        #expect(r.isTV == false)
    }

    @Test func remuxOutranksBluRayInTheSameName() {
        // A REMUX is the top source tier and always co-occurs with BluRay/UHD in the name. Because
        // reSource matches left-to-right, "BluRay" appears first and would win — so a true UHD remux
        // mis-ranks as BluRay (6) instead of REMUX (7) and the Add flow could pick a worse "best".
        let r = parser.parse("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.HDR.DTS-HD.MA.5.1-FraMeSToR.mkv")
        #expect(r.source == "REMUX")
        // A plain BluRay (no remux) must still classify as BluRay.
        #expect(parser.parse("Movie.2024.1080p.BluRay.x264-GRP.mkv").source == "BluRay")
    }

    @Test func parsesCamAndTelesyncSources() {
        // Brand-new theatrical releases — the source tag is how you tell a real cam from a fake.
        #expect(parser.parse("Obsession.2026.1080p.CAM.x264-DKS.mkv").source == "CAM")
        #expect(parser.parse("Obsession.2026.1080p.TELESYNC.x264-UNiON.mkv").source == "TELESYNC")
        #expect(parser.parse("Obsession.2025.D.TELECINE.1080p.mkv").source == "TELECINE")
        #expect(parser.parse("Obsession (2026) English HQ HDTS - 1080p - x264.mkv").source == "HDTS")
        // The title still stops cleanly before the source tag.
        #expect(parser.parse("Obsession.2026.1080p.CAM.x264-DKS.mkv").title == "Obsession")
        #expect(parser.parse("Obsession.2026.1080p.CAM.x264-DKS.mkv").year == 2026)
    }

    @Test func parsesAWebDLMovieWithAudio() {
        let r = parser.parse("Oppenheimer.2023.1080p.WEB-DL.DDP5.1.H264-EVO.mkv")
        #expect(r.title == "Oppenheimer")
        #expect(r.year == 2023)
        #expect(r.resolution == "1080p")
        #expect(r.source == "WEB-DL")
        #expect(r.videoCodec == "h264")
        #expect(r.audioCodec == "DDP5.1")
        #expect(r.releaseGroup == "EVO")
    }

    @Test func parsesSpaceSeparatedMovie() {
        let r = parser.parse("The Batman 2022 720p BluRay x264.mp4")
        #expect(r.title == "The Batman")
        #expect(r.year == 2022)
        #expect(r.resolution == "720p")
        #expect(r.videoCodec == "x264")
    }

    @Test func parsesStandardEpisode() {
        let r = parser.parse("Shogun.S01E03.1080p.WEB-DL.DDP5.1.x265-NTb.mkv")
        #expect(r.title == "Shogun")
        #expect(r.season == 1)
        #expect(r.episode == 3)
        #expect(r.isTV == true)
        #expect(r.resolution == "1080p")
    }

    @Test func parsesXFormatEpisode() {
        let r = parser.parse("Severance.2x05.720p.HDTV.x264-GROUP.mkv")
        #expect(r.title == "Severance")
        #expect(r.season == 2)
        #expect(r.episode == 5)
        #expect(r.source == "HDTV")
    }

    /// `S01.E01` — a separator between the season and episode tokens — is common in the wild and
    /// parsed as a season PACK with no episode. Two things went wrong downstream: size ranking
    /// exempts packs (nothing to compare a pack against), so a 40 GB single episode dodged the
    /// size policy entirely and outranked a right-sized one; and a pack whose FILES are named this
    /// way had every episode skipped when the library expanded it.
    @Test func parsesAnEpisodeWithASeparatorBetweenSeasonAndEpisode() {
        for name in ["Sherlock.S01.E01.A.Study.in.Pink.REMUX.2160p.selezen.mkv",
                     "Sherlock S01 E01 A Study in Pink 2160p.mkv",
                     "Sherlock.S01-E01.A.Study.in.Pink.2160p.mkv",
                     "Sherlock_S01_E01_A_Study_in_Pink.mkv"] {
            let r = parser.parse(name)
            #expect(r.season == 1, "season for \(name)")
            #expect(r.episode == 1, "episode for \(name)")
        }
    }

    /// The separator must not swallow a genuine season pack: `S01` followed by a word starting
    /// with E is still a pack, because an episode needs digits.
    @Test func aSeasonPackIsNotMistakenForAnEpisode() {
        let r = parser.parse("Fallout.S01.Extras.2160p.WEB-DL.mkv")
        #expect(r.season == 1)
        #expect(r.episode == nil)
    }

    @Test func parsesSeasonPack() {
        let r = parser.parse("Fallout.S01.2160p.AMZN.WEB-DL.DDP5.1.HDR.HEVC-FLUX")
        #expect(r.title == "Fallout")
        #expect(r.season == 1)
        #expect(r.episode == nil)
        #expect(r.isTV == true)
        #expect(r.videoCodec == "HEVC")
    }

    @Test func extractsTitleFromDottedNameWithNoYear() {
        let r = parser.parse("Some.Indie.Documentary.1080p.WEBRip.x264-AAA.mkv")
        #expect(r.title == "Some Indie Documentary")
        #expect(r.year == nil)
        #expect(r.resolution == "1080p")
    }

    @Test func stripsParenthesisedYearFromTitle() {
        // RD/scene names like "Split.(2016)..." must not leave "(2016)" in the title — that
        // breaks the TMDB enrichment query (and the added item shows no poster).
        let r = parser.parse("Split.(2016).UHD.BluRay.HDR.2160p.ITA.DTS.ENG.AC3.Subs.x265.[TbZ].mkv")
        #expect(r.title == "Split")
        #expect(r.year == 2016)
        #expect(r.resolution == "2160p")
    }

    @Test func keepsLeadingNumberThatIsNotAYearInTitle() {
        let r = parser.parse("21.Jump.Street.2012.1080p.BluRay.x264-SPARKS.mkv")
        #expect(r.title == "21 Jump Street")
        #expect(r.year == 2012)
        #expect(r.resolution == "1080p")
        #expect(r.releaseGroup == "SPARKS")
    }

    @Test func handlesNameWithNoRecognizableMetadata() {
        let r = parser.parse("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef.mkv")
        #expect(r.title == "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
        #expect(r.year == nil)
        #expect(r.isTV == false)
    }

    /// The release year was whichever year-shaped token came FIRST, so a film whose title contains
    /// a year handed TMDB the title's year and matched nothing (or the wrong film).
    @Test func aYearInsideTheTitleIsNotTheReleaseYear() {
        let r = parser.parse("Blade.Runner.2049.2017.2160p.BluRay.REMUX.x265-GRP.mkv")
        #expect(r.title == "Blade Runner 2049")
        #expect(r.year == 2017)
        #expect(r.resolution == "2160p")
    }

    /// …and the title has to keep that year, or "Blade Runner" + 2017 searches for the wrong film.
    @Test func aTitleThatIsAYearSurvivesAlongsideItsReleaseYear() {
        let r = parser.parse("2012.2009.1080p.BluRay.x264-SPARKS.mkv")
        #expect(r.title == "2012")
        #expect(r.year == 2009)
        #expect(r.releaseGroup == "SPARKS")
    }

    /// With only one year-shaped token and nothing before it, treating it as metadata left the
    /// title empty — and the empty-title fallback handed back the whole raw release string, which
    /// TMDB cannot match.
    @Test func aFilmNamedForAYearIsNotTitledWithItsWholeReleaseString() {
        let r = parser.parse("2012.1080p.BluRay.x264-SPARKS.mkv")
        #expect(r.title == "2012")
        #expect(r.year == nil)
        #expect(r.resolution == "1080p")
    }

    /// A double-episode file matched neither the season+episode pattern (the second `E` broke the
    /// trailing lookaround) nor the bare-season one, so it parsed as a MOVIE named for the show and
    /// the episodes never reached the library.
    @Test func aDoubleEpisodeFileIsStillAnEpisode() {
        let r = parser.parse("Some.Show.S01E01E02.1080p.WEB-DL.x264-GRP.mkv")
        #expect(r.title == "Some Show")
        #expect(r.season == 1)
        #expect(r.episode == 1)
        #expect(r.isTV == true)
    }

    @Test func aDoubleEpisodeFileWithSeparatorsIsStillAnEpisode() {
        let r = parser.parse("Some.Show.S02E13-E14.1080p.HDTV.x264.mkv")
        #expect(r.season == 2)
        #expect(r.episode == 13)
        #expect(r.isTV == true)
    }

    /// The release group is whatever trails the last hyphen — which, for a name that simply ends in
    /// a source tag, was half of that tag. "DL" then poisoned release-group matching when ranking
    /// subtitles.
    @Test func aTrailingSourceTagIsNotAReleaseGroup() {
        #expect(parser.parse("Some.Film.2024.1080p.WEB-DL.mkv").releaseGroup == nil)
        #expect(parser.parse("Some.Film.2024.2160p.Blu-Ray.mkv").releaseGroup == nil)
        #expect(parser.parse("Some.Film.2024.2160p.TrueHD.Atmos.DTS-HD.mkv").releaseGroup == nil)
        // …but a real group still is one.
        #expect(parser.parse("Some.Film.2024.1080p.WEB-DL.x264-NTb.mkv").releaseGroup == "NTb")
    }

    /// Bracketed fansub naming is the one common shape the token scan cannot see: the tags are
    /// glued to their brackets, so `[1080p]` never matches the resolution stop-pattern and the
    /// whole filename becomes the title. TMDB matches nothing against that, so the title shows no
    /// poster and no metadata at all.
    @Test func bracketedFansubNamingStillYieldsATitle() {
        let r = parser.parse("[SubsPlease] Some Show - 07 [1080p][HEVC].mkv")
        #expect(r.title == "Some Show")
        #expect(r.resolution == "1080p")
    }

    @Test func aBracketedYearAndTagsAreNotPartOfTheTitle() {
        let r = parser.parse("[Group] Another Title [2019] [720p] [x264].mkv")
        #expect(r.title == "Another Title")
        #expect(r.year == 2019)
        #expect(r.resolution == "720p")
    }

    /// A bracketed group at the END must not end up in the title.
    ///
    /// The first case passes with or without bracket handling — the year ends the title long before
    /// the tag — so on its own it proved nothing. The second is the one that actually exercises it:
    /// with no year and no metadata, the tag is all that can stop the title.
    @Test func aTrailingBracketedTagDoesNotEndUpInTheTitle() {
        #expect(parser.parse("Some.Film.2021.1080p.BluRay.x265.[TbZ].mkv").title == "Some Film")
        #expect(parser.parse("Some.Film.[TbZ].mkv").title == "Some Film")
    }

    // MARK: - Regressions caught reviewing the year/bracket work against itself

    /// A title that BEGINS with a year and continues is not just that year. Breaking at the leading
    /// year truncated "2012 Doomsday" to "2012" — which is a different film, and since a movie's
    /// key is its title they collapsed into one library entry.
    @Test func aTitleThatStartsWithAYearKeepsTheRestOfItself() {
        let r = parser.parse("2012.Doomsday.1080p.WEBRip.x264-GRP.mkv")
        #expect(r.title == "2012 Doomsday")
        #expect(r.year == nil)
    }

    @Test func twoFilmsWhoseTitlesBeginWithTheSameYearStayApart() {
        let a = parser.parse("2012.1080p.BluRay.x264-SPARKS.mkv")
        let b = parser.parse("2012.Doomsday.1080p.WEBRip.x264-GRP.mkv")
        #expect(a.title != b.title)
    }

    /// …and one that begins with a year AND carries a release year still splits them correctly.
    @Test func aYearTitleWithAReleaseYearStillSplits() {
        let r = parser.parse("2012.Doomsday.2008.1080p.WEBRip.mkv")
        #expect(r.title == "2012 Doomsday")
        #expect(r.year == 2008)
    }

    /// A fansub episode has to parse as an EPISODE. Reading the title but not the number left every
    /// episode of a series as a movie named for the show — so all of them collapsed into one entry.
    @Test func aFansubEpisodeIsAnEpisodeNotAMovie() {
        let r = parser.parse("[SubsPlease] Some Show - 07 [1080p][HEVC].mkv")
        #expect(r.title == "Some Show")
        #expect(r.episode == 7)
        #expect(r.isTV == true)
    }

    /// The `- <number>` rule must not touch ordinary release names, where a trailing hyphenated
    /// number is part of the title.
    @Test func aHyphenatedNumberInAnOrdinaryTitleIsNotAnEpisode() {
        let r = parser.parse("Mission.Impossible.-.2.2000.1080p.BluRay.x264.mkv")
        #expect(r.isTV == false)
        #expect(r.title.contains("2"))
        #expect(r.year == 2000)
    }

    /// A film whose title IS a bracketed token — [REC] — must keep it rather than being dropped as
    /// a group tag and falling back to the raw filename.
    @Test func aFilmTitledWithBracketsKeepsItsTitle() {
        let r = parser.parse("[REC].2007.1080p.BluRay.x264-GRP.mkv")
        #expect(r.title == "REC")
        #expect(r.year == 2007)
    }
}
