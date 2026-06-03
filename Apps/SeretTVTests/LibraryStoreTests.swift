import Testing
import Foundation
import DebridCore
@testable import Seret

private func movie(_ id: String, poster: String? = nil) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "Movie \(id)", year: 2024,
              sources: [], seasons: [], posterPath: poster)
}
private func show(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .show, title: "Show \(id)", year: 2023, sources: [], seasons: [])
}

private enum FakeError: Error { case boom }

/// Sendable seam double: values fixed at init, so there's no concurrent mutation.
private final class FakeLibrary: LibraryProviding {
    let cached: [MediaItem]?
    let refreshResult: Result<[MediaItem], FakeError>
    init(cached: [MediaItem]?, refresh: Result<[MediaItem], FakeError>) {
        self.cached = cached
        self.refreshResult = refresh
    }
    func loadCached() -> [MediaItem]? { cached }
    func refresh() async throws -> [MediaItem] { try refreshResult.get() }
}

@MainActor
@Suite struct LibraryStoreTests {
    @Test func cacheFirstLoadsAndSplitsByKind() async {
        let store = LibraryStore(library: FakeLibrary(
            cached: [movie("1"), show("2")], refresh: .success([movie("1"), show("2")])))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.movies.map(\.id) == ["1"])
        #expect(store.shows.map(\.id) == ["2"])
    }

    @Test func refreshFromColdCacheLoads() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .success([movie("1")])))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.movies.count == 1)
    }

    @Test func emptyLibraryIsEmptyState() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .success([])))
        await store.load()
        #expect(store.state == .empty)
    }

    @Test func failureWithNoCacheIsFailed() async {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .failure(.boom)))
        await store.load()
        guard case .failed = store.state else {
            #expect(Bool(false), "expected .failed, got \(store.state)"); return
        }
    }

    @Test func failureWithCacheKeepsShowingCache() async {
        let store = LibraryStore(library: FakeLibrary(cached: [movie("1")], refresh: .failure(.boom)))
        await store.load()
        #expect(store.state == .loaded)   // cache retained, not blanked
        #expect(store.movies.count == 1)
    }

    @Test func retryIncrementsAttempt() {
        let store = LibraryStore(library: FakeLibrary(cached: nil, refresh: .success([])))
        store.retry()
        #expect(store.attempt == 1)
        store.retry()
        #expect(store.attempt == 2)
    }
}
