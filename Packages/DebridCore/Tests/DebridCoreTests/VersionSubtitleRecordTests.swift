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

    @Test func playbackIsFoldedInNotSwappedIn() {
        // The player announces tracks one at a time; a partial report must not erase the header's.
        let header = VersionSubtitleRecord(origin: .header, fileName: "F.mkv", tracks: [hebrewText])
        let merged = header.merging(playback: [ContainerTrack(kind: .audio, language: "en", codec: "a52 ")])
        #expect(merged.origin == .playback)
        #expect(merged.fileName == "F.mkv")
        #expect(merged.hebrewLevel == .builtIn)
        #expect(merged.audioLanguages == ["en"])
    }

    @Test func aPlayerTrackBecomesAContainerTrack() {
        let track = ContainerTrack(MediaTrack(id: "spu/3", kind: .subtitle, name: "עברית",
                                              language: nil, codec: "bdpg"))
        #expect(track.kind == .subtitle)
        #expect(track.language == "he")
        #expect(track.isImageSubtitle)
    }
}
