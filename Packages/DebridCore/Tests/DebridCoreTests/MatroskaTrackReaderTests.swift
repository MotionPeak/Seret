import Testing
@testable import DebridCore

@Suite struct MatroskaTrackReaderTests {
    typealias T = EBML.Track

    private func tracks(_ result: MatroskaTrackReader.Result) -> [ContainerTrack]? {
        if case .tracks(let tracks) = result { return tracks }
        return nil
    }

    @Test func readsVideoAudioAndAHebrewTextSubtitle() {
        let file = EBML.file(tracks: [
            T(type: 1, codec: "V_MPEGH/ISO/HEVC", frameDuration: 41_708_333),
            T(type: 2, language: "eng", codec: "A_EAC3"),
            T(type: 17, language: "heb", codec: "S_TEXT/UTF8", name: "Hebrew"),
        ])
        let found = tracks(MatroskaTrackReader.read(file))
        #expect(found?.map(\.kind) == [.video, .audio, .subtitle])
        #expect(found?[1].language == "en")
        #expect(found?[2].language == "he")
        #expect(found?[2].isImageSubtitle == false)
        #expect(found?[0].frameRate == 23.976)
    }

    @Test func aPGSTrackIsAPictureSubtitle() {
        let file = EBML.file(tracks: [T(type: 17, language: "heb", codec: "S_HDMV/PGS")])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.isImageSubtitle == true)
    }

    @Test func theRetiredCodeIwIsHebrew() {
        let file = EBML.file(tracks: [T(type: 17, language: "iw")])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.language == "he")
    }

    @Test func bcp47WinsOverTheOldLanguageElement() {
        // The Matroska spec: when LanguageBCP47 is present, Language is ignored. The two must
        // disagree here — with "und" the old element normalises to nothing, and either order
        // would pass.
        let file = EBML.file(tracks: [T(type: 17, language: "eng", bcp47: "he-IL")])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.language == "he")
    }

    @Test func anUndeterminedTagFallsThroughToBCP47() {
        let file = EBML.file(tracks: [T(type: 17, language: "und", bcp47: "he-IL")])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.language == "he")
    }

    @Test func anUntaggedTrackNamedInHebrewCountsAsHebrew() {
        let file = EBML.file(tracks: [T(type: 17, language: "und", name: "עברית")])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.language == "he")
    }

    @Test func aMissingLanguageIsUnknownNotEnglish() {
        let file = EBML.file(tracks: [T(type: 17)])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.language == nil)
    }

    @Test func aForcedTrackIsMarked() {
        let file = EBML.file(tracks: [T(type: 17, language: "heb", forced: true)])
        #expect(tracks(MatroskaTrackReader.read(file))?.first?.isForced == true)
    }

    @Test func aWebMFileIsRead() {
        let file = EBML.file(tracks: [T(type: 17, language: "heb")], docType: "webm")
        #expect(tracks(MatroskaTrackReader.read(file))?.count == 1)
    }

    @Test func anotherEBMLDocumentIsNotMatroska() {
        let file = EBML.file(tracks: [T(type: 17, language: "heb")], docType: "notmkv")
        #expect(MatroskaTrackReader.read(file) == .notMatroska)
    }

    @Test func tracksPastTheBufferArePointedToByTheSeekHead() {
        let file = EBML.file(tracks: [T(type: 17, language: "heb")], padding: 300_000, seekHead: true)
        let head = Array(file.prefix(262_144))
        guard case .tracksAt(let offset) = MatroskaTrackReader.read(head) else {
            Issue.record("expected the SeekHead's offset")
            return
        }
        #expect(MatroskaTrackReader.readTracksElement(Array(file[offset...]))?.first?.language == "he")
    }

    @Test func aTrackListCutOffByTheBufferIsReReadFromItsStart() {
        // ~90 KB of track list starting ~200 KB in: it straddles the first window, and a second
        // window-sized read from its start holds all of it — exactly what the probe can do.
        let long = String(repeating: "x", count: 30_000)
        let file = EBML.file(tracks: (0..<3).map { _ in T(type: 17, language: "heb", name: long) },
                             padding: 200_000)
        let head = Array(file.prefix(ContainerProbe.window))
        guard case .tracksAt(let offset) = MatroskaTrackReader.read(head) else {
            Issue.record("expected the start of the cut-off Tracks element")
            return
        }
        let reread = Array(file[offset...].prefix(ContainerProbe.window))
        #expect(MatroskaTrackReader.readTracksElement(reread)?.count == 3)
    }

    /// The SeekHead is bytes off the network. Adding an offset near `Int.max` to the Segment's start
    /// trapped — a crash on opening the title page, every time, since a failed read is not kept.
    @Test func anAbsurdSeekHeadOffsetIsIncompleteNotACrash() {
        let positions: [UInt64] = [UInt64(Int.max), UInt64(Int.max) - 100, UInt64.max,
                                   UInt64(MatroskaTrackReader.maxFileOffset) + 1]
        for position in positions {
            #expect(MatroskaTrackReader.read(EBML.file(seekHeadPointingAt: position)) == .incomplete,
                    "position \(position)")
        }
    }

    @Test func aPlausibleSeekHeadOffsetIsStillFollowed() {
        guard case .tracksAt(let offset) = MatroskaTrackReader.read(EBML.file(seekHeadPointingAt: 5_000_000))
        else {
            Issue.record("expected the SeekHead's offset")
            return
        }
        #expect(offset > 5_000_000 && offset < 5_000_100)
    }

    @Test func notMatroskaAtAll() {
        #expect(MatroskaTrackReader.read(Array("....ftypisom".utf8)) == .notMatroska)
        #expect(MatroskaTrackReader.read([]) == .notMatroska)
    }

    @Test func garbageAfterTheHeaderIsIncompleteNotACrash() {
        let bytes = EBML.header() + [0x18, 0x53, 0x80, 0x67] + [UInt8](repeating: 0xFF, count: 64)
        #expect(MatroskaTrackReader.read(bytes) == .incomplete)
    }
}
