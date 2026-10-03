import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private struct ListReader: LetterboxdProfileReading {
    let slugs: [String]
    var error: (any Error)?

    func films() async throws -> [LetterboxdEntry] { [] }
    func watchlist() async throws -> [LetterboxdEntry] {
        if let error { throw error }
        return slugs.map { LetterboxdEntry(slug: $0, name: "\($0) (1994)", year: 1994, rating: nil) }
    }
}

/// Fails until healed — the same list read twice, the second time successfully.
private final class FlakyReader: LetterboxdProfileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var healed = false
    func heal() { lock.lock(); defer { lock.unlock() }; healed = true }

    func films() async throws -> [LetterboxdEntry] { [] }
    func watchlist() async throws -> [LetterboxdEntry] {
        let ok = lock.withLock { healed }
        guard ok else { throw LetterboxdError.transient("offline") }
        return [LetterboxdEntry(slug: "c", name: "c (1994)", year: 1994, rating: nil)]
    }
}

/// Every film's TMDB id is derived from its slug, so a film on both lists resolves to one id.
private struct SlugResolver: WatchlistTitleResolving {
    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        let slug = WatchlistName.stripYear(from: name)
        return WatchlistMatch(tmdbID: abs(slug.hashValue % 100_000) + 1, posterPath: "/\(slug).jpg")
    }
}

private func syncer(_ slugs: [String], error: (any Error)? = nil) -> WatchlistSyncer {
    WatchlistSyncer(reader: ListReader(slugs: slugs, error: error),
                    resolver: SlugResolver(),
                    store: WatchlistStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("combined-\(UUID().uuidString).json")),
                    resolveDelay: .zero)
}

@Suite struct CombinedWatchlistTests {

    /// With no partner, nothing about the watchlist may change.
    @Test func withoutAPartnerItIsTheOwnersList() async throws {
        let owner = syncer(["a", "b"])
        let combined = CombinedWatchlist(owner: owner, partner: nil, partnerName: nil)
        let synced = try await combined.sync(onProgress: nil)
        #expect(synced.map(\.slug) == ["a", "b"])
        #expect(await combined.status() == .solo)
    }

    @Test func aSyncShowsBothListsAsOne() async throws {
        let combined = CombinedWatchlist(owner: syncer(["a", "shared"]),
                                         partner: syncer(["shared", "c"]), partnerName: "Noga")
        let synced = try await combined.sync(onProgress: nil)
        #expect(synced.map(\.slug) == ["a", "shared", "c"])
        #expect(await combined.cached().map(\.slug) == ["a", "shared", "c"])
    }

    /// The partner's list failing must not cost the owner theirs.
    @Test func aPartnerFailureKeepsTheOwnersListAndSaysWhose() async throws {
        let combined = CombinedWatchlist(owner: syncer(["a"]),
                                         partner: syncer([], error: LetterboxdError.profileUnavailable),
                                         partnerName: "Noga")
        let synced = try await combined.sync(onProgress: nil)
        #expect(synced.map(\.slug) == ["a"])
        let error = try #require(await combined.status().partnerError)
        #expect(error.contains("Noga"))
    }

    @Test func aLaterSuccessClearsThePartnerError() async throws {
        let flaky = FlakyReader()
        let partner = WatchlistSyncer(reader: flaky, resolver: SlugResolver(),
                                      store: WatchlistStore(fileURL: FileManager.default.temporaryDirectory
                                          .appendingPathComponent("combined-\(UUID().uuidString).json")),
                                      resolveDelay: .zero)
        let combined = CombinedWatchlist(owner: syncer(["a"]), partner: partner, partnerName: "Noga")
        _ = try await combined.sync(onProgress: nil)
        #expect(await combined.status().partnerError != nil)

        flaky.heal()
        _ = try await combined.sync(onProgress: nil)
        #expect(await combined.status().partnerError == nil)
    }

    /// The owner's failure is still the screen's failure — but the partner's list is read anyway.
    @Test func anOwnerFailureThrowsButThePartnerIsStillRead() async {
        let partner = syncer(["c"])
        let combined = CombinedWatchlist(owner: syncer([], error: LetterboxdError.profileUnavailable),
                                         partner: partner, partnerName: "Noga")
        await #expect(throws: LetterboxdError.self) { _ = try await combined.sync(onProgress: nil) }
        #expect(await partner.cached().map(\.slug) == ["c"])
    }

    /// A shared film is hidden on both sides, and only the owner's side is ever sent anywhere.
    @Test func removingASharedFilmHidesItInBothAndPushesOnlyTheOwners() async throws {
        let owner = syncer(["shared"])
        let partner = syncer(["shared"])
        let combined = CombinedWatchlist(owner: owner, partner: partner, partnerName: "Noga")
        _ = try await combined.sync(onProgress: nil)

        let after = await combined.remove(slug: "shared")
        #expect(after.filter { !$0.isRemoved }.isEmpty)
        #expect(await owner.pendingRemovals().map(\.slug) == ["shared"])
        #expect(await partner.cached().first?.isRemoved == true)
    }

    @Test func removingAPartnersFilmLeavesTheOwnersListAlone() async throws {
        let owner = syncer(["a"])
        let partner = syncer(["c"])
        let combined = CombinedWatchlist(owner: owner, partner: partner, partnerName: "Noga")
        _ = try await combined.sync(onProgress: nil)

        let after = await combined.remove(slug: "c")
        #expect(after.filter { !$0.isRemoved }.map(\.slug) == ["a"])
        #expect(await owner.cached().allSatisfy { !$0.isRemoved })
        #expect(await owner.pendingRemovals().isEmpty)
    }

    /// The owner's own add of a film the partner lists carries a placeholder slug; the removal
    /// still has to find the partner's row, which only the TMDB id can do.
    @Test func removingByAPlaceholderSlugReachesThePartnersRow() async throws {
        let owner = syncer([])
        let partner = syncer(["heat"])
        let combined = CombinedWatchlist(owner: owner, partner: partner, partnerName: "Noga")
        _ = try await combined.sync(onProgress: nil)
        let heatID = try #require(await partner.cached().first?.tmdbID)
        _ = await combined.add(tmdbID: heatID, title: "heat", year: 1994, posterPath: nil)

        let after = await combined.remove(slug: WatchlistEntry.localSlug(forTMDB: heatID))
        #expect(after.filter { !$0.isRemoved }.isEmpty)
        #expect(await partner.cached().first?.isRemoved == true)
    }

    @Test func addingGoesToTheOwnersListOnly() async throws {
        let owner = syncer([])
        let partner = syncer(["c"])
        let combined = CombinedWatchlist(owner: owner, partner: partner, partnerName: "Noga")
        _ = try await combined.sync(onProgress: nil)

        _ = await combined.add(tmdbID: 42, title: "New", year: 2026, posterPath: nil)
        #expect(await owner.pendingAdds().map(\.tmdbID) == [42])
        #expect(await partner.cached().map(\.slug) == ["c"])
    }

    @Test func theStatusSaysWhoseListAFilmIsOn() async throws {
        let combined = CombinedWatchlist(owner: syncer(["a", "shared"]),
                                         partner: syncer(["shared", "c"]), partnerName: "Noga")
        let synced = try await combined.sync(onProgress: nil)
        let status = await combined.status()
        #expect(status.partnerName == "Noga")
        let bySlug = Dictionary(uniqueKeysWithValues: synced.map { ($0.slug, $0) })
        #expect(status.membership.holders(of: bySlug["a"]!) == .init(owner: true, partner: false))
        #expect(status.membership.holders(of: bySlug["shared"]!) == .init(owner: true, partner: true))
        #expect(status.membership.holders(of: bySlug["c"]!) == .init(owner: false, partner: true))
    }
}
