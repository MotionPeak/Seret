import Testing
@testable import DebridCore

@Suite struct SubtitleEvidenceSetTests {
    private func stream(_ hash: String, _ name: String, subs: [String] = [],
                        langs: [String] = []) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: name, parsed: FilenameParser().parse(name),
                     languages: langs, sizeBytes: nil, sourceName: nil, subtitleLanguages: subs)
    }

    private func owned(_ id: String, _ name: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)", parsed: FilenameParser().parse(name))
    }

    private let sparksHebrew = SubtitleResult(fileID: 1, language: "he",
                                              release: "Oppenheimer.2023.1080p.BluRay.x264-SPARKS")

    @Test func aSubtitleTagInTheNameIsBuiltIn() {
        let set = SubtitleEvidenceSet.candidates(
            [stream("a", "Oppenheimer.2023.1080p.HebSubs", subs: ["he"])],
            hebrewResults: [], originalLanguage: "en")
        #expect(set.hebrew(forVersion: "a") == .builtIn)
    }

    @Test func aSubtitleMadeForTheReleaseIsMatched() {
        let set = SubtitleEvidenceSet.candidates(
            [stream("a", "Oppenheimer.2023.1080p.BluRay.x264-SPARKS"),
             stream("b", "Oppenheimer.2023.2160p.WEB-DL.x265-FLUX")],
            hebrewResults: [sparksHebrew], originalLanguage: "en")
        #expect(set.hebrew(forVersion: "a") == .matched)
        #expect(set.hebrew(forVersion: "b") == .none)
    }

    @Test func aCandidatesAudioIsKnownFromItsName() {
        let set = SubtitleEvidenceSet.candidates([stream("a", "Film.2023.FRENCH.1080p", langs: ["fr"])],
                                                 hebrewResults: [], originalLanguage: "en")
        #expect(set[version: "a"]?.audioLanguages == ["fr"])
    }

    @Test func anOwnedCopyMatchesOnItsParsedRelease() {
        let source = owned("T", "Oppenheimer.2023.1080p.BluRay.x264-SPARKS.mkv")
        let set = SubtitleEvidenceSet.owned([source], records: [:], hebrewResults: [sparksHebrew],
                                            originalLanguage: "en")
        #expect(set.hebrew(forVersion: WatchKey.source(source)) == .matched)
    }

    @Test func whatTheFileCarriesBeatsAMatch() {
        let source = owned("T", "Oppenheimer.2023.1080p.BluRay.x264-SPARKS.mkv")
        let record = VersionSubtitleRecord(origin: .header, tracks: [
            ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8"),
            ContainerTrack(kind: .audio, language: "en")])
        let set = SubtitleEvidenceSet.owned([source], records: [WatchKey.source(source): record],
                                            hebrewResults: [sparksHebrew], originalLanguage: "en")
        #expect(set.hebrew(forVersion: WatchKey.source(source)) == .builtIn)
        #expect(set[version: WatchKey.source(source)]?.audioLanguages == ["en"])
    }

    @Test func theTitleLanguageIsNormalised() {
        #expect(SubtitleEvidenceSet.owned([], records: [:], hebrewResults: [], originalLanguage: "heb")
                    .originalLanguage == "he")
    }

    @Test func mergingKeepsTheNewerEvidence() {
        let early = SubtitleEvidenceSet(byVersion: ["a": SubtitleEvidence(hebrew: .none)], originalLanguage: "en")
        let late = SubtitleEvidenceSet(byVersion: ["a": SubtitleEvidence(hebrew: .matched)], originalLanguage: nil)
        let merged = early.merging(late)
        #expect(merged.hebrew(forVersion: "a") == .matched)
        #expect(merged.originalLanguage == "en")
    }

    @Test func theChipDescribesTheVersionPlayWillUse() {
        let playing = owned("P", "Film.2023.1080p.WEB-DL")
        let key = WatchKey.source(playing)
        func chip(_ level: HebrewSubtitles, results: [SubtitleResult]?) -> HebrewTitleChip? {
            HebrewTitleChip.forTitle(playing: playing,
                                     subtitles: SubtitleEvidenceSet(byVersion: [key: SubtitleEvidence(hebrew: level)]),
                                     hebrewResults: results)
        }
        #expect(chip(.builtInImage, results: []) == .builtIn)
        #expect(chip(.matched, results: []) == .matched)
        #expect(chip(.none, results: [sparksHebrew]) == .available)
        #expect(chip(.none, results: []) == nil)
        #expect(chip(.none, results: nil) == nil)
    }

    @Test func aFilmYouDoNotOwnCanStillShowAvailable() {
        #expect(HebrewTitleChip.forTitle(playing: nil, subtitles: .empty, hebrewResults: [sparksHebrew]) == .available)
    }

    @Test func theWordsOnTheBadges() {
        #expect(HebrewSubtitles.builtIn.badgeText == "Hebrew · Built in")
        #expect(HebrewSubtitles.builtInImage.badgeText == "Hebrew · Built in")
        #expect(HebrewSubtitles.matched.badgeText == "Hebrew · Matched")
        #expect(HebrewSubtitles.none.badgeText == nil)
        #expect(HebrewTitleChip.available.text == "Hebrew · Available")
    }
}
