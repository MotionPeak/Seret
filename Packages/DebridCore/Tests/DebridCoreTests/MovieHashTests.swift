import Testing
import Foundation
@testable import DebridCore

@Suite struct MovieHashTests {
    // Hand-computable vectors. 128 KB of zeros: every word adds 0, so the hash is the file size.
    // 128 KB of 0xFF: 16384 words of (2^64 - 1) ≡ -16384 mod 2^64, so hash = 131072 - 16384.
    @Test func allZeroChunksHashToTheFileSize() {
        let zeros = Data(repeating: 0x00, count: 65_536)
        #expect(MovieHash.compute(fileSize: 131_072, head: zeros, tail: zeros) == "0000000000020000")
    }

    @Test func allOnesWrapAroundOnOverflow() {
        let ones = Data(repeating: 0xFF, count: 65_536)
        #expect(MovieHash.compute(fileSize: 131_072, head: ones, tail: ones) == "000000000001c000")
    }

    @Test func aShortChunkIsRejected() {
        let zeros = Data(repeating: 0x00, count: 65_536)
        #expect(MovieHash.compute(fileSize: 100, head: Data(), tail: zeros) == nil)
        #expect(MovieHash.compute(fileSize: 100, head: zeros, tail: Data(repeating: 0, count: 10)) == nil)
    }

    @Test func theOutputIsAlwaysSixteenLowercaseHexCharacters() {
        let zeros = Data(repeating: 0x00, count: 65_536)
        let h = MovieHash.compute(fileSize: 1, head: zeros, tail: zeros)
        #expect(h?.count == 16)
        #expect(h == h?.lowercased())
    }
}
