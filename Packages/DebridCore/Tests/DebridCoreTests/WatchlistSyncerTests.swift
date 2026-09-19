import Testing
import Foundation
@testable import DebridCore

private struct FakeWatchlistReader: LetterboxdProfileReading {
    let entries: [LetterboxdEntry]
    let error: (any Error)?

    init(_ slugs: [String], error: (any Error)? = nil) {
        self.entries = slugs.map {
            LetterboxdEntry(slug: $0, name: "\($0) (1994)", year: 1994, rating: nil)
        }
        self.error = error
    }

    func films() async throws -> [LetterboxdEntry] { [] }

    func watchlist() async throws -> [LetterboxdEntry] {
        if let error { throw error }
        return entries
    }
}

final class ResolveCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func bump(_ name: String) { lock.lock(); defer { lock.unlock() }; names.append(name) }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

private struct FakeTitleResolver: WatchlistTitleResolving {
    let ids: [String: Int]
    let calls: ResolveCalls
    /// Thrown instead of answering — the search FAILING, which is a different outcome from the
    /// search succeeding and finding nothing.
    var failure: (any Error)?

    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        calls.bump(name)
        if let failure { throw failure }
        let key = WatchlistName.stripYear(from: name)
        guard let id = ids[key] else { return nil }
        return WatchlistMatch(tmdbID: id, posterPath: "/\(key).jpg")
    }
}

@Suite struct WatchlistSyncerTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wl-\(UUID().uuidString).json")
    }

    func syncer(_ slugs: [String], ids: [String: Int], url: URL,
                calls: ResolveCalls = ResolveCalls(), error: (any Error)? = nil,
                resolverFailure: (any Error)? = nil) -> WatchlistSyncer {
        WatchlistSyncer(reader: FakeWatchlistReader(slugs, error: error),
                        resolver: FakeTitleResolver(ids: ids, calls: calls, failure: resolverFailure),
                        store: WatchlistStore(fileURL: url),
                        resolveDelay: .zero)
    }

    @Test func crawlsResolvesAndPersists() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await syncer(["speed", "heat"],
                                      ids: ["speed": 1637, "heat": 949], url: url).sync()
        #expect(result.map(\.slug) == ["speed", "heat"])
        #expect(result[0].tmdbID == 1637)
        #expect(result[0].posterPath == "/speed.jpg")
        #expect(WatchlistStore(fileURL: url).load().map(\.tmdbID) == [1637, 949])
    }

    @Test func aSecondSyncResolvesNothingAgain() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let calls = ResolveCalls()

        _ = try await syncer(["speed"], ids: ["speed": 1637], url: url, calls: calls).sync()
        _ = try await syncer(["speed"], ids: ["speed": 1637], url: url, calls: calls).sync()

        #expect(calls.all.count == 1)
    }

    /// A film TMDB does not know is resolved once and then left alone, not retried every sync.
    @Test func anUnmatchedFilmIsNotRetriedForever() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let calls = ResolveCalls()

        _ = try await syncer(["mystery"], ids: [:], url: url, calls: calls).sync()
        let again = try await syncer(["mystery"], ids: [:], url: url, calls: calls).sync()

        #expect(calls.all.count == 1)
        #expect(again[0].isResolved)
        #expect(again[0].tmdbID == nil)
    }

    /// A search that FAILS is not a film TMDB does not know.
    ///
    /// The two were conflated: the resolver's error was swallowed and `resolvedAt` stamped anyway,
    /// so one network blip or rate-limit during the first sync marked those films "searched, found
    /// nothing" — permanently, because the syncer only ever retries what was never tried. A whole
    /// run of grey boxes could be nothing worse than a bad minute of Wi-Fi.
    @Test func aFailedSearchIsRetriedRatherThanRecordedAsNoSuchFilm() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try await syncer(["speed"], ids: ["speed": 1637], url: url,
                                     resolverFailure: URLError(.timedOut)).sync()
        #expect(first[0].tmdbID == nil)
        #expect(first[0].isResolved == false)   // never tried, as far as the mirror is concerned

        let second = try await syncer(["speed"], ids: ["speed": 1637], url: url).sync()
        #expect(second[0].tmdbID == 1637)
    }

    @Test func aRemovedFilmDisappears() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await syncer(["a", "b"], ids: ["a": 1, "b": 2], url: url).sync()
        let after = try await syncer(["a"], ids: ["a": 1], url: url).sync()
        #expect(after.map(\.slug) == ["a"])
    }

    /// A failed crawl must not empty the mirror — an empty screen after a blip reads as "gone".
    @Test func aFailedCrawlLeavesTheStoredMirrorIntact() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await syncer(["a"], ids: ["a": 1], url: url).sync()
        let failing = syncer([], ids: [:], url: url, error: LetterboxdError.profileUnavailable)

        await #expect(throws: LetterboxdError.profileUnavailable) { _ = try await failing.sync() }
        #expect(WatchlistStore(fileURL: url).load().map(\.slug) == ["a"])
        #expect(await failing.cached().map(\.slug) == ["a"])
    }

    @Test func progressIsReportedPerResolvedFilm() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let seen = ResolveCalls()

        _ = try await syncer(["a", "b"], ids: ["a": 1, "b": 2], url: url)
            .sync(onProgress: { done, total in seen.bump("\(done)/\(total)") })
        #expect(seen.all == ["1/2", "2/2"])
    }
}
