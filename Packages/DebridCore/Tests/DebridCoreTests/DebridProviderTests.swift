import Testing
import Foundation
@testable import DebridCore

@Suite struct DebridProviderTests {
    struct StubTokens: AccessTokenProviding {
        func validAccessToken() async throws -> String { "TESTTOKEN" }
    }

    @Test func torrentIDPrefixPicksTheProvider() {
        #expect(DebridProvider.of(torrentID: "tb:42") == .torBox)
        #expect(DebridProvider.of(torrentID: "ABCDEF123") == .realDebrid)
    }

    @Test func linkPrefixPicksTheProvider() {
        #expect(DebridProvider.of(link: "torbox://tb:42/3") == .torBox)
        #expect(DebridProvider.of(link: "https://real-debrid.com/d/XYZ") == .realDebrid)
    }

    @Test func displayNames() {
        #expect(DebridProvider.realDebrid.displayName == "Real-Debrid")
        #expect(DebridProvider.torBox.displayName == "TorBox")
    }

    @Test func listingDefaultsToNothingUnavailable() {
        let listing = TorrentListing(torrents: [])
        #expect(listing.unavailable.isEmpty)
        #expect(listing == TorrentListing(torrents: [], unavailable: []))
    }

    @Test func torrentsClientIsARealDebridDebridClient() {
        let c: any DebridClient = TorrentsClient(tokens: StubTokens())
        #expect(c.provider == .realDebrid)
    }
}
