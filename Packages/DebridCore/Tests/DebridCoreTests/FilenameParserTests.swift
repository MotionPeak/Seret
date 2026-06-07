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
}
