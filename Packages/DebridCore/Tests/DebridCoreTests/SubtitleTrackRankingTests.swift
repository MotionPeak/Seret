import Testing
@testable import DebridCore

/// Choosing a subtitle track has to consider what KIND it is, not just its language.
///
/// A Blu-ray rip carries `bdpg` — PGS — which is not text at all but a sequence of pre-rendered
/// images. Picking one has consequences the language alone cannot express: it ignores every font,
/// size and colour preference the app offers (they apply to rendered text), it cannot be retimed by
/// `SubtitleRetimer`, and each cue is a bitmap to decode and composite, which is the first thing to
/// suffer when the pipeline is under load.
@Suite struct SubtitleTrackRankingTests {

    private func sub(_ id: String, _ codec: String?, _ lang: String?) -> MediaTrack {
        MediaTrack(id: id, kind: .subtitle, name: id, language: lang, codec: codec)
    }

    @Test func aBitmapTrackIsRecognisedByItsCodec() {
        #expect(sub("spu/0", "bdpg", "en").isBitmapSubtitle)   // Blu-ray PGS
        #expect(sub("spu/0", "spu ", "en").isBitmapSubtitle)   // DVD VobSub
        #expect(sub("spu/0", "dvbs", "en").isBitmapSubtitle)   // DVB
        #expect(sub("spu/0", "XSUB", "en").isBitmapSubtitle)   // case-insensitive
    }

    @Test func aTextTrackIsNotABitmapOne() {
        #expect(!sub("spu/0", "subt", "en").isBitmapSubtitle)
        #expect(!sub("spu/0", "ssa ", "en").isBitmapSubtitle)
        #expect(!sub("spu/0", "ass ", "en").isBitmapSubtitle)
        // Unknown codec is assumed to be text: guessing "bitmap" would demote a perfectly good
        // track on no evidence, and the cost of that is worse than the cost of not promoting it.
        #expect(!sub("spu/0", nil, "en").isBitmapSubtitle)
        #expect(!sub("spu/0", "wxyz", "en").isBitmapSubtitle)
    }

    @Test func textIsChosenOverABitmapTrackInTheSameLanguage() {
        // The defect this pins: selection took the FIRST track matching the language, and on a
        // REMUX the bitmap tracks are listed first, so the app reliably picked the one that
        // ignores the viewer's font settings and drops cues under load.
        let tracks = [sub("spu/5", "bdpg", "en"), sub("spu/6", "subt", "en")]
        #expect(tracks.bestSubtitle(forLanguage: "en")?.id == "spu/6")
    }

    @Test func aBitmapTrackIsStillChosenWhenItIsAllThereIs() {
        let tracks = [sub("spu/5", "bdpg", "en")]
        #expect(tracks.bestSubtitle(forLanguage: "en")?.id == "spu/5")
    }

    @Test func orderIsOtherwisePreservedWithinAKind() {
        let tracks = [sub("spu/1", "subt", "en"), sub("spu/2", "subt", "en")]
        #expect(tracks.bestSubtitle(forLanguage: "en")?.id == "spu/1")
    }

    @Test func aDifferentLanguageIsNeverChosen() {
        let tracks = [sub("spu/5", "bdpg", "fr"), sub("spu/6", "subt", "de")]
        #expect(tracks.bestSubtitle(forLanguage: "en") == nil)
    }

    @Test func theLanguageStemStillMatches() {
        let tracks = [sub("spu/5", "subt", "en-GB")]
        #expect(tracks.bestSubtitle(forLanguage: "en")?.id == "spu/5")
    }

    @Test func onlyBitmapTracksInTheLanguageIsReportable() {
        // Drives the download fallback: a text subtitle fetched from OpenSubtitles is strictly
        // better than a bitmap one — it honours the font settings and can be retimed.
        #expect([sub("spu/5", "bdpg", "en")].hasOnlyBitmapSubtitles(forLanguage: "en"))
        #expect(![sub("spu/5", "bdpg", "en"), sub("spu/6", "subt", "en")]
            .hasOnlyBitmapSubtitles(forLanguage: "en"))
        // No track in the language at all is NOT "only bitmap" — that is the existing no-track
        // case, which already has its own path.
        #expect(![sub("spu/5", "bdpg", "fr")].hasOnlyBitmapSubtitles(forLanguage: "en"))
    }
}
