import Testing
import Foundation
import SwiftData
@testable import DebridCore

/// In-memory fakes rather than `MockURLProtocol`: this suite needs SwiftData, so it must nest under
/// `SwiftDataSuite`, and anything touching the mock's shared handler must nest under `MockTests`.
/// A suite cannot be under both, and one that tries races and breaks unrelated suites.
private struct FakeProfileReader: LetterboxdProfileReading {
    let entries: [LetterboxdEntry]
    func films() async throws -> [LetterboxdEntry] { entries }
    func watchlist() async throws -> [LetterboxdEntry] { [] }
}

private struct FakeResolver: LetterboxdFilmResolving {
    let slugs: [Int: String]
    let calls: CallCounter

    func slug(forTMDB id: Int) async throws -> String {
        calls.bump()
        guard let slug = slugs[id] else { throw LetterboxdError.filmNotFound }
        return slug
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() { lock.lock(); defer { lock.unlock() }; value += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LetterboxdImporter.Progress] = []

    func record(_ p: LetterboxdImporter.Progress) {
        lock.lock(); defer { lock.unlock() }
        values.append(p)
    }

    var all: [LetterboxdImporter.Progress] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

extension SwiftDataSuite {
    @Suite struct LetterboxdImporterTests {
        func makeStore() throws -> LocalWatchStore {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchStore(modelContainer: c)
        }

        func movie(tmdb: Int, title: String) -> MediaItem {
            MediaItem(id: "movie:tmdb:\(tmdb)", kind: .movie, title: title, year: 1994,
                      sources: [], seasons: [], tmdbID: tmdb)
        }

        func entry(_ slug: String, _ rating: Int?) -> LetterboxdEntry {
            LetterboxdEntry(slug: slug, name: "\(slug) (1994)", year: 1994, rating: rating)
        }

        func makeImporter(store: LocalWatchStore,
                          entries: [LetterboxdEntry],
                          slugs: [Int: String],
                          calls: CallCounter = CallCounter(),
                          mapStore: LetterboxdFilmMapStore = LetterboxdFilmMapStore(fileURL: nil))
        -> LetterboxdImporter {
            LetterboxdImporter(reader: FakeProfileReader(entries: entries),
                               resolver: FakeResolver(slugs: slugs, calls: calls),
                               map: LetterboxdFilmMap(),
                               mapStore: mapStore,
                               store: store,
                               resolveDelay: .zero)
        }

        @Test func writesARatingSeretDoesNotHave() async throws {
            let store = try makeStore()
            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", 6)],
                                                 slugs: [1637: "speed"])
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.written == 1)
            #expect(try await store.rating(forContentKey: "movie:tmdb:1637", profileID: "owner") == 6)
        }

        @Test func leavesAnExistingRatingAlone() async throws {
            let store = try makeStore()
            try await store.setRating(9, contentKey: "movie:tmdb:1637", profileID: "owner")

            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", 6)],
                                                 slugs: [1637: "speed"])
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.written == 0)
            #expect(summary.conflicts == 1)
            #expect(try await store.rating(forContentKey: "movie:tmdb:1637", profileID: "owner") == 9)
        }

        /// An already-rated film IS resolved, because a disagreement cannot be seen otherwise —
        /// but it counts as needing no work, since local wins and nothing will be written.
        @Test func anAlreadyRatedFilmCountsAsNeedingNoWork() async throws {
            let store = try makeStore()
            try await store.setRating(9, contentKey: "movie:tmdb:1637", profileID: "owner")

            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", 6)],
                                                 slugs: [1637: "speed"])
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.scanned == 1)
            #expect(summary.needingWork == 0)
            #expect(summary.written == 0)
        }

        @Test func aFilmLetterboxdDoesNotKnowIsCountedNotFatal() async throws {
            let store = try makeStore()
            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", 6)],
                                                 slugs: [:])
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.unresolved == 1)
            #expect(summary.written == 0)
        }

        @Test func anUnratedLetterboxdEntryWritesNothing() async throws {
            let store = try makeStore()
            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", nil)],
                                                 slugs: [1637: "speed"])
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.written == 0)
            #expect(try await store.rating(forContentKey: "movie:tmdb:1637", profileID: "owner") == nil)
        }

        @Test func reportsProgressAsItGoes() async throws {
            let store = try makeStore()
            let seen = ProgressLog()
            _ = try await makeImporter(store: store,
                                       entries: [entry("speed", 6), entry("heat", 9)],
                                       slugs: [1637: "speed", 949: "heat"])
                .run(movies: [movie(tmdb: 1637, title: "Speed"), movie(tmdb: 949, title: "Heat")],
                     profileID: "owner",
                     onProgress: { seen.record($0) })
            #expect(seen.all.count == 2)
            #expect(seen.all.last?.total == 2)
            #expect(seen.all.last?.done == 2)
        }

        @Test func aShowIsNeverConsidered() async throws {
            let store = try makeStore()
            let show = MediaItem(id: "show:tmdb:1396", kind: .show, title: "Breaking Bad", year: 2008,
                                 sources: [], seasons: [], tmdbID: 1396)
            let summary = try await makeImporter(store: store,
                                                 entries: [entry("speed", 6)],
                                                 slugs: [1637: "speed"])
                .run(movies: [show], profileID: "owner")
            #expect(summary.scanned == 0)
        }

        @Test func eachFilmIsResolvedExactlyOncePerRun() async throws {
            let store = try makeStore()
            let calls = CallCounter()
            _ = try await makeImporter(store: store,
                                       entries: [entry("speed", 6)],
                                       slugs: [1637: "speed"],
                                       calls: calls)
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(calls.count == 1)
        }

        /// The resolved map is written out, so the next launch starts with it. Resolution being a
        /// one-time cost depends on this actually happening.
        @Test func theResolvedMapIsPersisted() async throws {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lbimport-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }

            let store = try makeStore()
            _ = try await makeImporter(store: store,
                                       entries: [entry("speed", 6)],
                                       slugs: [1637: "speed"],
                                       mapStore: LetterboxdFilmMapStore(fileURL: url))
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")

            #expect(LetterboxdFilmMapStore(fileURL: url).load() == [1637: "speed"])
        }
    }
}
