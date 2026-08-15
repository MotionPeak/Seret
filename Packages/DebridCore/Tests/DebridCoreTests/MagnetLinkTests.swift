import Testing
@testable import DebridCore

@Suite struct MagnetLinkTests {
    // 40-hex ↔ base32 pair, verified against RFC 4648 base32 of the same 20 bytes.
    static let hex = "0123456789abcdef0123456789abcdef01234567"
    static let base32 = "AERUKZ4JVPG66AJDIVTYTK6N54ASGRLH"

    @Test func parsesHexMagnet() {
        let link = MagnetLink.parse("magnet:?xt=urn:btih:\(Self.hex)")
        #expect(link?.infoHash == Self.hex)
        #expect(link?.displayName == nil)
    }

    @Test func lowercasesUppercaseHex() {
        let link = MagnetLink.parse("magnet:?xt=urn:btih:\(Self.hex.uppercased())")
        #expect(link?.infoHash == Self.hex)
    }

    @Test func decodesBase32Hash() {
        let link = MagnetLink.parse("magnet:?xt=urn:btih:\(Self.base32)")
        #expect(link?.infoHash == Self.hex)
    }

    @Test func extractsDisplayName() {
        let link = MagnetLink.parse("magnet:?xt=urn:btih:\(Self.hex)&dn=HaPijamot.S01E01.HDTV")
        #expect(link?.displayName == "HaPijamot.S01E01.HDTV")
    }

    @Test func decodesPercentAndPlusInDisplayName() {
        let link = MagnetLink.parse("magnet:?xt=urn:btih:\(Self.hex)&dn=Ha+Pijamot%20S01E01")
        #expect(link?.displayName == "Ha Pijamot S01E01")
    }

    @Test func acceptsBareHash() {
        #expect(MagnetLink.parse(Self.hex)?.infoHash == Self.hex)
        #expect(MagnetLink.parse("  \(Self.hex)  ")?.infoHash == Self.hex)
    }

    @Test func rejectsJunk() {
        #expect(MagnetLink.parse("") == nil)
        #expect(MagnetLink.parse("hello world") == nil)
        #expect(MagnetLink.parse("https://example.com/x.torrent") == nil)
        #expect(MagnetLink.parse("magnet:?dn=NoHashHere") == nil)          // no xt
        #expect(MagnetLink.parse("magnet:?xt=urn:sha1:\(Self.hex)") == nil) // wrong urn
        #expect(MagnetLink.parse("magnet:?xt=urn:btih:\(String(Self.hex.dropLast()))") == nil) // 39 chars
        #expect(MagnetLink.parse("magnet:?xt=urn:btih:\(String(repeating: "z", count: 40))") == nil) // non-hex
        #expect(MagnetLink.parse("magnet:?xt=urn:btih:\(String(repeating: "1", count: 32))") == nil) // 1 not in base32
    }
}
