import Testing
@testable import DebridCore

/// Ranking audio tracks by how reliably tvOS/VLCKit can actually render them.
///
/// The bug this exists to prevent: a REMUX lists its lossless track FIRST (TrueHD Atmos /
/// DTS-HD MA) with the AC-3 compatibility track below it. Picking "the first English track"
/// therefore picked the one VLC is worst at — silence where it cannot decode at all, and
/// audio-only dropouts (video stays smooth, because that is hardware-decoded) where it can
/// decode but cannot sustain it.
struct AudioTrackRankingTests {

    private func track(_ id: String, _ codec: String?, _ language: String? = "eng",
                       channels: Int? = nil) -> MediaTrack {
        MediaTrack(id: id, kind: .audio, name: id, language: language,
                   codec: codec, channels: channels)
    }

    private func commentary(_ id: String, _ codec: String?, _ language: String?) -> MediaTrack {
        MediaTrack(id: id, kind: .audio, name: "Commentary by director Florian Henckel von Donnersmarck",
                   language: language, codec: codec, channels: 2)
    }

    /// Commentary tracks are told apart by the name the release gives them — the one thing VLCKit
    /// passes through (MKV's FlagCommentary is not exposed).
    @Test func commentaryIsRecognisedByItsName() {
        func named(_ name: String) -> MediaTrack { MediaTrack(id: "a", kind: .audio, name: name, language: "en") }
        #expect(named("Commentary by director Florian Henckel von Donnersmarck").isCommentary)
        #expect(named("Director's commentary").isCommentary)
        #expect(named("Audiokommentar").isCommentary)
        #expect(named("Commentaire du réalisateur").isCommentary)
        #expect(!named("English").isCommentary)
        #expect(!named("DTS-HD MA 5.1").isCommentary)
        #expect(!named("EN").isCommentary)
    }

    /// The Lives of Others (MrTentsaw release): German main mix, and the only English track is the
    /// director's commentary. A language match must never land on a commentary — there the
    /// English preference has nothing to offer, and the main mix in the film's own language wins.
    @Test func bestAudioNeverPicksACommentary() {
        let tracks = [track("main", "dts ", "ger"), commentary("en-comm", "a52 ", "en"),
                      commentary("de-comm", "a52 ", "ger")]
        #expect(tracks.bestAudio(forLanguage: "en") == nil)
        #expect(tracks.bestAudio(forLanguage: "ger")?.id == "main")   // DTS main over AC-3 commentary
    }

    @Test func acThreeOutranksTrueHDEvenWhenTrueHDIsListedFirst() {
        let tracks = [track("truehd", "trhd", channels: 8), track("ac3", "a52 ", channels: 6)]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["ac3", "truehd"])
    }

    @Test func dtsSitsBetweenReliableAndTrueHD() {
        let tracks = [track("truehd", "trhd"), track("dts", "dts "), track("eac3", "eac3")]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["eac3", "dts", "truehd"])
    }

    @Test func mlpIsTreatedAsTrueHD() {
        let tracks = [track("mlp", "mlp "), track("aac", "mp4a")]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["aac", "mlp"])
    }

    /// Stability matters: within one tier the file's own order is the author's intent (main mix
    /// first, commentary later). Ranking must not reshuffle it.
    @Test func equalTierKeepsTheFileOrder() {
        let tracks = [track("main", "a52 "), track("commentary", "a52 "), track("aac", "mp4a")]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["main", "commentary", "aac"])
    }

    /// An untagged codec must not be demoted below a known-bad one — unknown is not "unreliable".
    @Test func unknownCodecRanksAboveTrueHD() {
        let tracks = [track("truehd", "trhd"), track("unknown", nil)]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["unknown", "truehd"])
    }

    @Test func fourccMatchingIgnoresCaseAndPadding() {
        let tracks = [track("truehd", "TRHD"), track("ac3", "A52")]
        #expect(tracks.mostDecodableFirst().map(\.id) == ["ac3", "truehd"])
    }

    // MARK: - Picking for a language

    @Test func bestForLanguagePrefersTheDecodableTrackInThatLanguage() {
        let tracks = [track("eng-truehd", "trhd", "eng"),
                      track("eng-ac3", "a52 ", "eng"),
                      track("fre-ac3", "a52 ", "fre")]
        #expect(tracks.bestAudio(forLanguage: "eng")?.id == "eng-ac3")
    }

    @Test func bestForLanguageIsNilWhenTheLanguageIsAbsent() {
        #expect([track("eng", "a52 ", "eng")].bestAudio(forLanguage: "heb") == nil)
    }

    /// Language tags arrive as "en", "eng", "en-US" or "English" depending on the container.
    @Test func bestForLanguageMatchesTheTagVariants() {
        let tracks = [track("a", "trhd", "en-US"), track("b", "a52 ", "English")]
        #expect(tracks.bestAudio(forLanguage: "en")?.id == "b")
    }

    @Test func rankingOnlyConsidersAudioTracks() {
        let mixed = [MediaTrack(id: "sub", kind: .subtitle, name: "sub", language: "eng"),
                     track("ac3", "a52 ")]
        #expect(mixed.mostDecodableFirst().map(\.id) == ["ac3"])
    }
}
