import Testing
@testable import DebridCore

@Suite struct VersionSubtitleRecordTests {
    private let hebrewText = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")
    private let hebrewPictures = ContainerTrack(kind: .subtitle, language: "he", codec: "S_HDMV/PGS")

    @Test func aHebrewTextTrackIsBuiltIn() {
        #expect(VersionSubtitleRecord(origin: .header, tracks: [hebrewText]).hebrewLevel == .builtIn)
    }

    @Test func onlyPictureTracksAreBuiltInImage() {
        #expect(VersionSubtitleRecord(origin: .header, tracks: [hebrewPictures]).hebrewLevel == .builtInImage)
    }

    @Test func textBeatsPicturesWhenAFileHasBoth() {
        let record = VersionSubtitleRecord(origin: .header, tracks: [hebrewPictures, hebrewText])
        #expect(record.hebrewLevel == .builtIn)
    }

    @Test func aForcedHebrewTrackDoesNotCount() {
        let forced = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8", isForced: true)
        #expect(VersionSubtitleRecord(origin: .header, tracks: [forced]).hebrewLevel == .none)
    }

    @Test func aHebSubNameIsBuiltInWhateverTheTracksSay() {
        let record = VersionSubtitleRecord(origin: .unreadable, fileName: "Film.2023.1080p.HebSubs.mp4")
        #expect(record.hebrewLevel == .builtIn)
    }

    @Test func englishOnlyIsNone() {
        let english = ContainerTrack(kind: .subtitle, language: "en", codec: "S_TEXT/UTF8")
        #expect(VersionSubtitleRecord(origin: .header, tracks: [english]).hebrewLevel == .none)
    }

    @Test func audioLanguagesAreListedOnce() {
        let record = VersionSubtitleRecord(origin: .header, tracks: [
            ContainerTrack(kind: .audio, language: "en"), ContainerTrack(kind: .audio, language: "en"),
            ContainerTrack(kind: .audio, language: "fr"),
        ])
        #expect(record.audioLanguages == ["en", "fr"])
        #expect(VersionSubtitleRecord(origin: .header, tracks: [hebrewText]).audioLanguages == nil)
    }

    @Test func anUntaggedAudioTrackMakesTheAudioUnknown() {
        // Read off a real file: Arrival's "Multi" UHD release has an untagged first audio track —
        // almost certainly the English original — then French and Spanish. Listing only the tagged
        // two called it a dub that had lost the film's own language.
        let record = VersionSubtitleRecord(origin: .header, tracks: [
            ContainerTrack(kind: .audio, language: nil), ContainerTrack(kind: .audio, language: "fr"),
            ContainerTrack(kind: .audio, language: "es"),
        ])
        #expect(record.audioLanguages == nil)
    }

    @Test func theVideoFrameRateIsKept() {
        let record = VersionSubtitleRecord(origin: .header, tracks: [
            ContainerTrack(kind: .video, language: nil, frameRate: 23.976)])
        #expect(record.frameRate == 23.976)
    }

    /// A header read is the file's own index. The player sees the same tracks with less detail —
    /// no forced flag, a fourcc for a codec — and appending its copies turned a forced-only Hebrew
    /// track into "Built in" after a single play, for good.
    @Test func aHeaderReadIsKeptAsReadWhateverPlaybackSees() {
        let forced = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8",
                                    name: "Hebrew Forced", isForced: true)
        let header = VersionSubtitleRecord(origin: .header, fileName: "F.mkv", tracks: [
            ContainerTrack(kind: .audio, language: "en", codec: "A_EAC3"), forced])
        let seen = [ContainerTrack(kind: .audio, language: "en", codec: "eac3"),
                    ContainerTrack(kind: .subtitle, language: "he", codec: "subt", name: "Hebrew")]
        #expect(header.merging(playback: seen) == header)
        #expect(header.merging(playback: seen).hebrewLevel == .none)
    }

    @Test func playbackFillsAFileTheHeaderCouldNotRead() {
        let mp4 = VersionSubtitleRecord(origin: .unreadable, fileName: "F.mp4")
        let merged = mp4.merging(playback: [hebrewText, ContainerTrack(kind: .audio, language: "en")])
        #expect(merged.origin == .unreadable)          // the read is still done: nothing to redo
        #expect(merged.isFinal)
        #expect(merged.fileName == "F.mp4")
        #expect(merged.hebrewLevel == .builtIn)
        #expect(merged.audioLanguages == ["en"])
    }

    /// What only the player reported is not final: the header still has to be read, for the forced
    /// flags, the frame rate and the file's own name.
    @Test func aRecordOnlyThePlayerMadeIsNotFinal() {
        #expect(!VersionSubtitleRecord(origin: .playback, tracks: [hebrewText]).isFinal)
        #expect(VersionSubtitleRecord(origin: .header).isFinal)
        #expect(VersionSubtitleRecord(origin: .unreadable).isFinal)
    }

    @Test func playbackReportsAddUp() {
        // The player announces tracks one at a time; a partial report must not erase an earlier one.
        let first = VersionSubtitleRecord(origin: .playback, tracks: [hebrewText])
        let merged = first.merging(playback: [ContainerTrack(kind: .audio, language: "en", codec: "a52 ")])
        #expect(merged.hebrewLevel == .builtIn)
        #expect(merged.audioLanguages == ["en"])
    }

    @Test func aPlayerTrackNamedForcedIsForced() {
        let track = ContainerTrack(MediaTrack(id: "spu/4", kind: .subtitle, name: "Hebrew (Forced)",
                                              language: "he", codec: "subt"))
        #expect(track.isForced)
        #expect(VersionSubtitleRecord(origin: .playback, tracks: [track]).hebrewLevel == .none)
    }

    @Test func aPlayerTrackBecomesAContainerTrack() {
        let track = ContainerTrack(MediaTrack(id: "spu/3", kind: .subtitle, name: "עברית",
                                              language: nil, codec: "bdpg"))
        #expect(track.kind == .subtitle)
        #expect(track.language == "he")
        #expect(track.isImageSubtitle)
    }
}
