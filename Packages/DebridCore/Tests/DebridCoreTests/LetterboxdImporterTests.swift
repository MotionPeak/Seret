import Testing
import Foundation
import SwiftData
@testable import DebridCore

final class ResolveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
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

        /// Serves the profile grid, then a redirect per film resolution.
        func install(ratings: [(slug: String, rating: Int)], slugForTMDB: [Int: String]) {
            MockURLProtocol.handler = { request in
                let url = request.url!
                if url.path.contains("/films/") {
                    let items = ratings.map { entry in
                        "<li class=\"griditem\"><div data-item-slug=\"\(entry.slug)\" data-item-name=\"\(entry.slug) (1994)\"></div><p><span class=\"rating rated-\(entry.rating)\">x</span></p></li>"
                    }.joined()
                    let body = "<html><body><ul>\(items)</ul></body></html>"
                    return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            Data(body.utf8))
                }
                let id = Int(url.pathComponents.filter { $0 != "/" }.last ?? "") ?? -1
                guard let slug = slugForTMDB[id] else {
                    return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
                }
                let final = URL(string: "https://letterboxd.com/film/\(slug)/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        func makeImporter(store: LocalWatchStore) -> LetterboxdImporter {
            let http = HTTPClient(session: .mock)
            let map = LetterboxdFilmMap()
            return LetterboxdImporter(
                reader: LetterboxdProfileReader(http: http, username: "thebigshin", pageDelay: .zero),
                resolver: LetterboxdFilmResolver(http: http, map: map),
                map: map,
                mapStore: LetterboxdFilmMapStore(fileURL: nil),
                store: store,
                resolveDelay: .zero)
        }

        @Test func writesARatingSeretDoesNotHave() async throws {
            let store = try makeStore()
            install(ratings: [("speed", 6)], slugForTMDB: [1637: "speed"])
            defer { MockURLProtocol.handler = nil }

            let summary = try await makeImporter(store: store)
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.written == 1)
            #expect(try await store.rating(forContentKey: "movie:tmdb:1637", profileID: "owner") == 6)
        }

        @Test func leavesAnExistingRatingAlone() async throws {
            let store = try makeStore()
            try await store.setRating(9, contentKey: "movie:tmdb:1637", profileID: "owner")
            install(ratings: [("speed", 6)], slugForTMDB: [1637: "speed"])
            defer { MockURLProtocol.handler = nil }

            let summary = try await makeImporter(store: store)
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.written == 0)
            #expect(summary.conflicts == 1)
            #expect(try await store.rating(forContentKey: "movie:tmdb:1637", profileID: "owner") == 9)
        }

        /// An already-rated film IS resolved, because a disagreement cannot be seen otherwise —
        /// but it is counted as needing no work, since local wins and nothing will be written.
        @Test func anAlreadyRatedFilmCountsAsNeedingNoWork() async throws {
            let store = try makeStore()
            try await store.setRating(9, contentKey: "movie:tmdb:1637", profileID: "owner")
            install(ratings: [("speed", 6)], slugForTMDB: [1637: "speed"])
            defer { MockURLProtocol.handler = nil }

            let summary = try await makeImporter(store: store)
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.scanned == 1)
            #expect(summary.needingWork == 0)
            #expect(summary.written == 0)
        }

        /// The cache is what keeps resolution a one-time cost. A second run must resolve nothing.
        @Test func aSecondRunResolvesNothingOverTheNetwork() async throws {
            let store = try makeStore()
            let resolves = ResolveCounter()
            MockURLProtocol.handler = { request in
                let url = request.url!
                if url.path.contains("/films/") {
                    let body = "<html><body><ul><li class=\"griditem\"><div data-item-slug=\"speed\" data-item-name=\"speed (1994)\"></div><p><span class=\"rating rated-6\">x</span></p></li></ul></body></html>"
                    return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            Data(body.utf8))
                }
                resolves.bump()
                let final = URL(string: "https://letterboxd.com/film/speed/")!
                return (HTTPURLResponse(url: final, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            defer { MockURLProtocol.handler = nil }

            let importer = makeImporter(store: store)
            let films = [movie(tmdb: 1637, title: "Speed")]
            _ = try await importer.run(movies: films, profileID: "owner")
            let afterFirst = resolves.count
            _ = try await importer.run(movies: films, profileID: "owner")

            #expect(afterFirst == 1)
            #expect(resolves.count == 1)   // the second run resolved nothing
        }

        @Test func aFilmLetterboxdDoesNotKnowIsCountedNotFatal() async throws {
            let store = try makeStore()
            install(ratings: [("speed", 6)], slugForTMDB: [:])    // every resolution 404s
            defer { MockURLProtocol.handler = nil }

            let summary = try await makeImporter(store: store)
                .run(movies: [movie(tmdb: 1637, title: "Speed")], profileID: "owner")
            #expect(summary.unresolved == 1)
            #expect(summary.written == 0)
        }

        @Test func reportsProgressAsItGoes() async throws {
            let store = try makeStore()
            install(ratings: [("speed", 6), ("heat", 9)], slugForTMDB: [1637: "speed", 949: "heat"])
            defer { MockURLProtocol.handler = nil }

            let seen = ProgressLog()
            _ = try await makeImporter(store: store).run(
                movies: [movie(tmdb: 1637, title: "Speed"), movie(tmdb: 949, title: "Heat")],
                profileID: "owner",
                onProgress: { seen.record($0) })
            #expect(seen.all.count == 2)
            #expect(seen.all.last?.total == 2)
            #expect(seen.all.last?.done == 2)
        }

        @Test func aShowIsNeverConsidered() async throws {
            let store = try makeStore()
            install(ratings: [("speed", 6)], slugForTMDB: [1637: "speed"])
            defer { MockURLProtocol.handler = nil }

            let show = MediaItem(id: "show:tmdb:1396", kind: .show, title: "Breaking Bad", year: 2008,
                                 sources: [], seasons: [], tmdbID: 1396)
            let summary = try await makeImporter(store: store).run(movies: [show], profileID: "owner")
            #expect(summary.scanned == 0)
        }
    }
}
