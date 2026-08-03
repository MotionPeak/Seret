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
