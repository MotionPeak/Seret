import Testing
@testable import DebridCore

/// A theatre copy must never take the Hebrew boost — and `FilenameParser` names only some of them
/// (HDCAM, HDTS, TELESYNC…), so `TS`, `TC`, `SCR` and friends are read off the raw release name.
@Suite struct TheatreReleaseTests {

    @Test(arguments: [
        "Movie.2023.1080p.TS.x264.HebSubs-GRP",
        "Movie.2023.HDTC.x264-GRP",
        "Movie.2023.DVDSCR.XviD-GRP",
        "Movie 2023 HQCAM x264",
        "Movie.2023.720p.HD-TS.x264",
        "Movie.2023.TELESYNC.x264",
        "Movie.2023.PDVD.x264",
        "Movie.2023.SCR.x264-GRP",
        "Movie.2023.TC.x264-GRP",
        "Movie.2023.CAMRip.x264",
        "Show.S01E02.720p.HDTS.x264",
    ])
    func aTheatreTagIsRecognised(_ name: String) {
        #expect(isTheatreRelease(named: name))
    }

    @Test(arguments: [
        "Cam.2018.1080p.NF.WEB-DL.DDP5.1.x264-NTG",       // the film is called "Cam"
        "Movie.2023.1080p.WEB-DL.DTS-HD.MA.5.1-GRP",       // DTS is not TS
        "Movie.2023.1080p.BluRay.x264.ts",                 // an MPEG-TS file, not a telesync
        "Movie.2023.2160p.UHD.BluRay.REMUX.HEVC-GRP",
        "Tsotsi.2005.1080p.BluRay.x264",
        "Movie.2023.1080p.HDTV.x264",
        "Movie.2023.1080p.WEB-DL.HebSubs",
    ])
    func anOrdinaryReleaseIsNot(_ name: String) {
        #expect(!isTheatreRelease(named: name))
    }

    @Test func aTelesyncWithHebrewSubtitlesDoesNotJumpACleanCopy() {
        let ts = CachedStream(infoHash: "ts", fileIdx: nil, rawTitle: "Movie.2023.1080p.TS.x264.HebSubs-GRP",
                              parsed: FilenameParser().parse("Movie.2023.1080p.TS.x264.HebSubs-GRP"),
                              languages: [], sizeBytes: nil, sourceName: nil,
                              subtitleLanguages: ["he"])
        let web = CachedStream(infoHash: "web", fileIdx: nil, rawTitle: "Movie.2023.2160p.WEB-DL.x265-GRP",
                               parsed: FilenameParser().parse("Movie.2023.2160p.WEB-DL.x265-GRP"),
                               languages: [], sizeBytes: nil, sourceName: nil)
        let evidence = SubtitleEvidenceSet.candidates([ts, web], hebrewResults: [], originalLanguage: "en")
        #expect(evidence.hebrew(forVersion: "ts") == .builtIn)       // the badge still shows
        #expect([ts, web].rankedFor(originalLanguage: "en", subtitles: evidence).first?.infoHash == "web")
    }

    @Test func anOwnedTelesyncIsKnownByItsFileName() {
        let parsed = FilenameParser().parse("Movie.2023.1080p.TS.x264-GRP")
        let ts = MediaSource(torrentID: "a", fileID: 1, restrictedLink: "https://rd/a", parsed: parsed)
        let web = MediaSource(torrentID: "b", fileID: 1, restrictedLink: "https://rd/b",
                              parsed: FilenameParser().parse("Movie.2023.2160p.WEB-DL.x265-GRP"))
        let hebrew = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")
        let records = [WatchKey.source(ts): VersionSubtitleRecord(origin: .header,
                                                                  fileName: "Movie.2023.1080p.TS.x264-GRP.mkv",
                                                                  tracks: [hebrew])]
        let evidence = SubtitleEvidenceSet.owned([ts, web], records: records, hebrewResults: [],
                                                 originalLanguage: "en")
        #expect([ts, web].bestFirst(subtitles: evidence).first == web)
    }
}
