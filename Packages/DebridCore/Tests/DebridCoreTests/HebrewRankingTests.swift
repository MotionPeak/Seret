import Testing
@testable import DebridCore

@Suite struct HebrewRankingTests {
    // MARK: search results

    private func stream(_ hash: String, _ res: String, source: String? = nil, langs: [String] = [],
                        audio: String? = nil) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: hash,
                     parsed: ParsedRelease(title: "T", resolution: res, source: source, audioCodec: audio),
                     languages: langs, sizeBytes: nil, sourceName: nil)
    }

    private func evidence(_ levels: [String: HebrewSubtitles], audio: [String: [String]] = [:],
                          original: String? = "en") -> SubtitleEvidenceSet {
        SubtitleEvidenceSet(
            byVersion: levels.reduce(into: [:]) { set, pair in
                set[pair.key] = SubtitleEvidence(hebrew: pair.value, audioLanguages: audio[pair.key])
            },
            originalLanguage: original)
    }

    @Test func aHebrewVersionOutranksEveryOtherEven720pOver2160p() {
        let uhd = stream("uhd", "2160p"), sd = stream("sd", "720p")
        let ranked = [uhd, sd].rankedFor(originalLanguage: "en", subtitles: evidence(["sd": .matched]))
        #expect(ranked.map(\.infoHash) == ["sd", "uhd"])
    }

    @Test func builtInBeatsPicturesBeatsMatched() {
        let a = stream("a", "2160p"), b = stream("b", "2160p"), c = stream("c", "2160p")
        let ranked = [a, b, c].rankedFor(originalLanguage: "en",
                                          subtitles: evidence(["a": .matched, "b": .builtIn, "c": .builtInImage]))
        #expect(ranked.map(\.infoHash) == ["b", "c", "a"])
    }

    @Test func withNothingKnownTheOrderIsTodays() {
        let list = [stream("a", "720p"), stream("b", "2160p", langs: ["fr"]), stream("c", "1080p")]
        let none = evidence(["a": .none, "b": .none, "c": .none])
        #expect(list.rankedFor(originalLanguage: "en", subtitles: none).map(\.infoHash)
                == list.rankedFor(originalLanguage: "en").map(\.infoHash))
        #expect(list.rankedFor(originalLanguage: "en").map(\.infoHash) == ["c", "a", "b"])
    }

    @Test func aDubStaysBelowTheOriginalWhateverItsSubtitles() {
        let dub = stream("dub", "2160p", langs: ["fr"]), original = stream("orig", "720p", langs: ["en"])
        let ranked = [dub, original].rankedFor(originalLanguage: "en", subtitles: evidence(["dub": .builtIn]))
        #expect(ranked.first?.infoHash == "orig")
    }

    @Test func aSilentFileStaysBelowOneThatPlaysWhateverItsSubtitles() {
        let silent = stream("mute", "1080p", audio: "TrueHD"), playable = stream("ok", "720p")
        let ranked = [silent, playable].rankedFor(originalLanguage: "en", subtitles: evidence(["mute": .builtIn]))
        #expect(ranked.first?.infoHash == "ok")
    }

    @Test func aTheatreRecordingNeverJumps() {
        let cam = stream("cam", "720p", source: "HDCAM"), web = stream("web", "1080p", source: "WEB-DL")
        let ranked = [cam, web].rankedFor(originalLanguage: "en", subtitles: evidence(["cam": .builtIn]))
        #expect(ranked.first?.infoHash == "web")
    }

    @Test func aFilmInHebrewGetsNoBoost() {
        let sd = stream("sd", "720p"), uhd = stream("uhd", "2160p")
        let ranked = [sd, uhd].rankedFor(originalLanguage: "he",
                                          subtitles: evidence(["sd": .builtIn], original: "he"))
        #expect(ranked.first?.infoHash == "uhd")
    }

    @Test func getBestTakesTheHebrewVersion() {
        let uhd = stream("uhd", "2160p"), sd = stream("sd", "720p")
        let match = [uhd, sd].bestMatch(originalLanguage: "en", subtitles: evidence(["sd": .builtIn]))
        #expect(match?.stream.infoHash == "sd")
        #expect(match?.isFallback == false)
    }

    // MARK: owned copies

    private func owned(_ id: String, _ res: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "T", resolution: res))
    }

    private func ownedEvidence(_ levels: [MediaSource: HebrewSubtitles],
                               audio: [MediaSource: [String]] = [:],
                               original: String? = "en") -> SubtitleEvidenceSet {
        var byVersion: [String: SubtitleEvidence] = [:]
        for (source, level) in levels {
            byVersion[WatchKey.source(source)] = SubtitleEvidence(hebrew: level, audioLanguages: audio[source])
        }
        return SubtitleEvidenceSet(byVersion: byVersion, originalLanguage: original)
    }

    @Test func anOwnedHebrewCopyIsWhatPlayPicks() {
        let uhd = owned("A", "2160p"), hd = owned("B", "1080p")
        let subtitles = ownedEvidence([hd: .builtIn])
        #expect([uhd, hd].bestFirst(subtitles: subtitles) == [hd, uhd])
        #expect([uhd, hd].preferred(nil, subtitles: subtitles) == hd)
    }

    @Test func aChosenCopyStillWins() {
        let uhd = owned("A", "2160p"), hd = owned("B", "1080p")
        #expect([uhd, hd].preferred(WatchKey.source(uhd), subtitles: ownedEvidence([hd: .builtIn])) == uhd)
    }

    @Test func anOwnedDubGetsNoBoost() {
        let dub = owned("A", "720p"), original = owned("B", "1080p")
        let subtitles = ownedEvidence([dub: .builtIn], audio: [dub: ["fr"], original: ["en"]])
        #expect([dub, original].bestFirst(subtitles: subtitles).first == original)
    }

    @Test func aDualAudioCopyKeepsItsBoost() {
        let dual = owned("A", "720p"), plain = owned("B", "1080p")
        let subtitles = ownedEvidence([dual: .matched], audio: [dual: ["en", "fr"]])
        #expect([dual, plain].bestFirst(subtitles: subtitles).first == dual)
    }

    @Test func withNothingKnownOwnedOrderIsTodays() {
        let list = [owned("A", "720p"), owned("B", "2160p"), owned("C", "1080p")]
        #expect(list.bestFirst(subtitles: .empty) == list.bestFirst())
        #expect(list.bestFirst().map(\.torrentID) == ["B", "C", "A"])
    }
}
