import Testing
@testable import DebridCore

@Suite struct MagnetStreamTests {
    static let hex = "0123456789abcdef0123456789abcdef01234567"

    @Test func carriesHashAndParsesDisplayName() {
        let link = MagnetLink(infoHash: Self.hex, displayName: "HaPijamot.S01E01.1080p.WEB-DL.x264")
        let stream = CachedStream.fromMagnet(link)
        #expect(stream.infoHash == Self.hex)
        #expect(stream.rawTitle == "HaPijamot.S01E01.1080p.WEB-DL.x264")
        #expect(stream.parsed.season == 1)
        #expect(stream.parsed.episode == 1)
        #expect(stream.parsed.resolution == "1080p")
        #expect(stream.isCached == false)   // a pasted magnet is never known-instant
        #expect(stream.sourceName == "Magnet")
    }

    @Test func fallsBackToHashWhenUnnamed() {
        let stream = CachedStream.fromMagnet(MagnetLink(infoHash: Self.hex))
        #expect(stream.rawTitle == Self.hex)
        #expect(stream.sizeBytes == nil)
        #expect(stream.fileIdx == nil)
    }
}
