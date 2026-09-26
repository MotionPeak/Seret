import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private func movie(_ id: String) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "T", year: 2024, sources: [], seasons: [])
}

private func mediaSource(_ torrentID: String, resolution: String? = nil, source: String? = nil,
                         videoCodec: String? = nil) -> MediaSource {
    MediaSource(torrentID: torrentID, fileID: 1, restrictedLink: "https://rd/d/\(torrentID)",
               parsed: ParsedRelease(title: "T", resolution: resolution, source: source,
                                    videoCodec: videoCodec))
}

private func movie(_ id: String, sources: [MediaSource]) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: "T", year: 2024, sources: sources, seasons: [])
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

    // MARK: - removeVersionReportingFailure (Task 2: lifted from tvOS's DetailView.performVersionRemove)

    @Test func removingOneOfTwoVersionsKeepsTheTitle() async {
        let a = mediaSource("a", resolution: "1080p")
        let b = mediaSource("b", resolution: "2160p")
        let item = movie("1", sources: [a, b])
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [item]))
        await store.load()

        let result = await store.removeVersionReportingFailure(store.movies[0], source: a)

        #expect(result == .removed(wasLast: false))
        #expect(store.movies.count == 1)
        #expect(store.movies[0].sources == [b])
    }

    @Test func removingTheLastVersionTakesTheTitle() async {
        let a = mediaSource("a", resolution: "1080p")
        let item = movie("1", sources: [a])
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [item]))
        await store.load()

        let result = await store.removeVersionReportingFailure(store.movies[0], source: a)

        #expect(result == .removed(wasLast: true))
        #expect(store.movies.isEmpty)
    }

    @Test func aRefusedVersionRemovalHandsBackTheMessageAndClearsIt() async {
        let a = mediaSource("a", resolution: "1080p")
        let item = movie("1", sources: [a])
        let store = LibraryStore(library: RemoveFakeLibrary(cached: [item], removeError: .boom))
        await store.load()

        let result = await store.removeVersionReportingFailure(store.movies[0], source: a)

        #expect(result == .failed("Couldn\u{2019}t remove that version. Please try again."))
        #expect(store.removal == .idle)
        #expect(store.movies.count == 1)
    }

    @Test func theVersionSummaryNamesResolutionSourceCodec() {
        let source = mediaSource("a", resolution: "1080p", source: "TELESYNC", videoCodec: "x264")
        #expect(source.versionSummary == "1080p \u{00B7} TELESYNC \u{00B7} x264")
    }

    @Test func aSourceWithNothingParsedIsThisVersion() {
        #expect(mediaSource("a").versionSummary == "This version")
    }
}
