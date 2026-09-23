import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private func movie(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "T", year: 2024, sources: [], seasons: [])
}

private final class RemoveFakeLibrary: LibraryProviding {
    let cached: [MediaItem]
    let removeError: FakeError?
    init(cached: [MediaItem], removeError: FakeError? = nil) {
        self.cached = cached; self.removeError = removeError
    }
    func loadCached() -> [MediaItem]? { cached }
    func refresh() async throws -> [MediaItem] { cached }
    func remove(_ item: MediaItem) async throws { if let e = removeError { throw e } }
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {
        if let e = removeError { throw e }
    }
}

@MainActor
@Suite struct LibraryStoreRemovalReportTests {
    @Test func aSuccessfulRemovalReportsNothing() async {
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [movie("1")]))
        await store.load()

        let message = await store.removeReportingFailure(store.movies[0])

        #expect(message == nil)
        #expect(store.movies.isEmpty)
        #expect(store.removal == .idle)
    }

    @Test func aRefusedRemovalHandsBackTheMessageAndClearsIt() async {
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [movie("1")], removeError: .boom))
        await store.load()
        let item = store.movies[0]

        let message = await store.removeReportingFailure(item)

        #expect(message == "Couldn\u{2019}t remove \u{201C}T\u{201D}. Please try again.")
        #expect(store.removal == .idle)
        #expect(store.movies.count == 1)
    }
}
