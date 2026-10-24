import Testing
@testable import DebridUI
import DebridCore

/// Add, download and delete copy names the account the action touches — with both accounts
/// signed in, "Real-Debrid" for a TorBox add or a TorBox torrent is false.
@MainActor
@Suite struct DebridCopyTests {
    private func source(_ torrentID: String) -> MediaSource {
        MediaSource(torrentID: torrentID, fileID: nil, restrictedLink: "x",
                    parsed: ParsedRelease(title: "Dune", resolution: nil))
    }

    @Test func accountsNamesEachProviderOnce() {
        #expect(DebridCopy.accounts([.torBox]) == "your TorBox account")
        #expect(DebridCopy.accounts([.torBox, .realDebrid, .torBox]) == "your Real-Debrid and TorBox accounts")
        #expect(DebridCopy.accounts([DebridProvider]()) == "your debrid account")
    }

    @Test func providersOfATitleCoverEveryVersion() {
        let movie = Fixture.movie(sources: [source("R1"), source("tb:9")])
        #expect(DebridCopy.providers(of: movie) == [.realDebrid, .torBox])
        #expect(DebridCopy.providers(of: Fixture.movie(sources: [source("tb:1")])) == [.torBox])
    }

    @Test func oneAccountHintNamesTheOther() {
        #expect(DebridCopy.addAccountHint(signedIn: [.realDebrid]) == "Sign in to TorBox too to see titles from both accounts.")
        #expect(DebridCopy.addAccountHint(signedIn: [.torBox]) == "Sign in to Real-Debrid too to see titles from both accounts.")
        #expect(DebridCopy.addAccountHint(signedIn: [DebridProvider]())
                == "Sign in to Real-Debrid and TorBox to see titles from both in one library.")
    }

    @Test func downloadCaptionNamesTheAddTarget() {
        #expect(VersionGroup.Availability.download.caption(downloadsTo: .torBox) == "Downloads to TorBox first, then plays.")
        #expect(VersionGroup.Availability.instant.caption(downloadsTo: .torBox) == "Plays right away.")
    }

    @Test func aDownloadWithNoTorrentYetIsOnTheAddTarget() {
        let pending = DownloadStatus(torrentID: "", contentKey: "k", tmdbID: 1, phase: .queued, fraction: 0)
        #expect(pending.torrentID.isEmpty)
        #expect(pending.provider(orElse: .torBox) == .torBox)
    }
}
