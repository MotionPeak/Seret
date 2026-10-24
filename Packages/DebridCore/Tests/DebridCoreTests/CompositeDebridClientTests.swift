import Testing
import Foundation
@testable import DebridCore

/// Pure: two in-memory accounts behind one composite. No network, no SwiftData.
@Suite struct CompositeDebridClientTests {
    private let rdMovie = FakeDebridClient.torrent("R1", provider: .realDebrid, filename: "Alpha.2024.1080p.mkv")
    private let tbMovie = FakeDebridClient.torrent("tb:1", provider: .torBox, filename: "Beta.2024.1080p.mkv")

    private func accounts(rdFailing: Bool = false, tbFailing: Bool = false)
        -> (rd: FakeDebridClient, tb: FakeDebridClient, log: FakeDebridCallLog) {
        let log = FakeDebridCallLog()
        let rd = FakeDebridClient(provider: .realDebrid, listed: [rdMovie], failing: rdFailing, log: log)
        let tb = FakeDebridClient(provider: .torBox, listed: [tbMovie], failing: tbFailing, log: log)
        return (rd, tb, log)
    }

    // MARK: - Routing

    @Test func routesInfoByPrefix() async throws {
        let (rd, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        #expect(try await composite.info(id: "tb:1").id == "tb:1")
        #expect(try await composite.info(id: "R1").id == "R1")
        try await composite.deleteTorrent(id: "tb:1")
        try await composite.deleteTorrent(id: "R1")
        let info = FakeDebridClient.info(of: tbMovie, provider: .torBox)
        _ = try await composite.playableURL(for: info)

        #expect(log.all == ["torBox.info(tb:1)", "realDebrid.info(R1)",
                            "torBox.deleteTorrent(tb:1)", "realDebrid.deleteTorrent(R1)",
                            "torBox.playableURL(tb:1)"])
    }

    @Test func routesUnrestrictByLinkScheme() async throws {
        let (rd, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let tbLink = try await composite.unrestrict(link: "torbox://tb:1/1")
        let rdLink = try await composite.unrestrict(link: "https://real-debrid.com/d/R1")

        #expect(tbLink.filename == "torBox")
        #expect(rdLink.filename == "realDebrid")
        #expect(log.all == ["torBox.unrestrict(torbox://tb:1/1)",
                            "realDebrid.unrestrict(https://real-debrid.com/d/R1)"])
    }

    @Test func addGoesToTarget() async throws {
        let (rd, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .torBox)

        #expect(composite.provider == .torBox)
        #expect(try await composite.add(magnetHash: "abc").id == "tb:new")
        #expect(try await composite.addForDownload(magnetHash: "def").id == "tb:new")
        #expect(log.all == ["torBox.add(abc)", "torBox.addForDownload(def)"])
    }

    @Test func addTargetFallsBackToTheFirstClientWhenItIsNotSignedIn() async throws {
        let (_, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [tb], addTarget: .realDebrid)

        #expect(composite.provider == .torBox)
        #expect(composite.providers == [.torBox])
        _ = try await composite.add(magnetHash: "abc")
        #expect(log.all == ["torBox.add(abc)"])
    }

    @Test func missingProviderThrowsNotSignedIn() async throws {
        let (_, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [tb], addTarget: .torBox)

        #expect(composite.client(for: .realDebrid) == nil)
        await #expect(throws: DebridRoutingError.notSignedIn(.realDebrid)) {
            _ = try await composite.info(id: "R1")
        }
        await #expect(throws: DebridRoutingError.notSignedIn(.realDebrid)) {
            _ = try await composite.unrestrict(link: "https://real-debrid.com/d/R1")
        }
        await #expect(throws: DebridRoutingError.notSignedIn(.realDebrid)) {
            try await composite.deleteTorrent(id: "R1")
        }
        await #expect(throws: DebridRoutingError.notSignedIn(.realDebrid)) {
            _ = try await composite.playableURL(for: FakeDebridClient.info(of: rdMovie, provider: .realDebrid))
        }
        #expect(log.all.isEmpty)   // never handed to the wrong account
    }

    // MARK: - Listing

    @Test func listTorrentsConcatenatesEveryAccountInClientOrder() async throws {
        let (rd, tb, _) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let listing = try await composite.listTorrents()
        #expect(listing.torrents.map(\.id) == ["R1", "tb:1"])
        #expect(listing.unavailable.isEmpty)
        #expect(try await composite.allTorrents().map(\.id) == ["R1", "tb:1"])
    }

    @Test func listTorrentsPartialFailureNamesUnavailable() async throws {
        let (rd, tb, _) = accounts(rdFailing: true)
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let listing = try await composite.listTorrents()
        #expect(listing.torrents.map(\.id) == ["tb:1"])
        #expect(listing.unavailable == [.realDebrid])
    }

    @Test func listTorrentsAllFailThrows() async throws {
        let (rd, tb, _) = accounts(rdFailing: true, tbFailing: true)
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        await #expect(throws: FakeDebridError.self) { _ = try await composite.listTorrents() }
        await #expect(throws: FakeDebridError.self) { _ = try await composite.allTorrents() }
    }

    /// The download monitor's page: each account's first page, with a failed account named.
    @Test func listingPagePartialFailureNamesUnavailable() async throws {
        let (rd, tb, _) = accounts(tbFailing: true)
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let page = try await composite.listing(page: 1, limit: 100)
        #expect(page.torrents.map(\.id) == ["R1"])
        #expect(page.unavailable == [.torBox])

        let (rd2, tb2, _) = accounts(rdFailing: true, tbFailing: true)
        let down = CompositeDebridClient(clients: [rd2, tb2], addTarget: .realDebrid)
        await #expect(throws: FakeDebridError.self) { _ = try await down.listing(page: 1, limit: 100) }
    }

    /// The download monitor reads a recorded download missing from page 1 as removed. TorBox's
    /// `mylist` order is not documented, so page 1 of TorBox is its WHOLE list (one call — TorBox
    /// has no per-torrent cost); Real-Debrid keeps its newest-first page.
    @Test func listingPageOneHoldsTorBoxsWholeList() async throws {
        let log = FakeDebridCallLog()
        let rdMany = (1...150).map { FakeDebridClient.torrent("R\($0)", provider: .realDebrid, filename: "r\($0).mkv") }
        let tbMany = (1...150).map { FakeDebridClient.torrent("tb:\($0)", provider: .torBox, filename: "t\($0).mkv") }
        let rd = FakeDebridClient(provider: .realDebrid, listed: rdMany, log: log)
        let tb = FakeDebridClient(provider: .torBox, listed: tbMany, log: log)
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let first = try await composite.listing(page: 1, limit: 100)
        #expect(first.torrents.filter { $0.id.hasPrefix("R") }.count == 100)
        #expect(first.torrents.filter { $0.id.hasPrefix("tb:") }.map(\.id) == tbMany.map(\.id))
        #expect(log.all.contains("torBox.allTorrents"))
        #expect(!log.all.contains("torBox.torrents"))

        let second = try await composite.listing(page: 2, limit: 100)
        #expect(second.torrents.map(\.id) == rdMany.dropFirst(100).map(\.id))
        #expect(second.unavailable.isEmpty)
        #expect(log.all.filter { $0.hasPrefix("torBox.") } == ["torBox.allTorrents"], "page 2 asked TorBox again")
    }

    /// A plain `[Torrent]` page has no way to say an account was missing, so it never quietly
    /// drops one: a caller would read those torrents as deleted.
    @Test func torrentsPageConcatenatesAndFailsWhenAnyAccountFails() async throws {
        let (rd, tb, _) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)
        #expect(try await composite.torrents(page: 1, limit: 50).map(\.id) == ["R1", "tb:1"])

        let (rd2, tb2, _) = accounts(rdFailing: true)
        let half = CompositeDebridClient(clients: [rd2, tb2], addTarget: .realDebrid)
        await #expect(throws: FakeDebridError.down(.realDebrid)) {
            _ = try await half.torrents(page: 1, limit: 50)
        }
    }

    @Test func allTorrentInfosSplitsByProviderAndKeepsInputOrder() async throws {
        let (rd, tb, log) = accounts()
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        let infos = try await composite.allTorrentInfos(from: [tbMovie, rdMovie])
        #expect(infos.map(\.id) == ["tb:1", "R1"])
        #expect(Set(log.all) == ["torBox.allTorrentInfos(tb:1)", "realDebrid.allTorrentInfos(R1)"])
    }

    @Test func allTorrentInfosAsksOnlyTheAccountsInvolved() async throws {
        let (rd, tb, log) = accounts(rdFailing: true)
        let composite = CompositeDebridClient(clients: [rd, tb], addTarget: .realDebrid)

        #expect(try await composite.allTorrentInfos(from: [tbMovie]).map(\.id) == ["tb:1"])
        #expect(try await composite.allTorrentInfos(from: []).isEmpty)
        #expect(log.all == ["torBox.allTorrentInfos(tb:1)"])
    }
}
