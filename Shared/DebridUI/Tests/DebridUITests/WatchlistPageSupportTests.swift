import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private func film(_ slug: String, _ position: Int, id: Int) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                   tmdbID: id, posterPath: "/\(id).jpg", resolvedAt: Date())
}

/// The pieces the Apple TV's Watchlist page adds to shared types — additive, so iPhone and Mac
/// behave exactly as before.
@MainActor
@Suite struct WatchlistPageSupportTests {

    /// A film added on a title page (or removed there) reaches a Watchlist page that stayed alive
    /// behind it: the page re-reads the mirror without a crawl.
    @Test func reloadCachedPicksUpChangesMadeElsewhere() async {
        let model = WatchlistModel(cached: [film("a", 0, id: 1)],
                                   settings: LetterboxdSettings(username: "x"),
                                   reload: { [film("new", -1, id: 9), film("a", 0, id: 1)] },
                                   run: { _ in [] })
        await model.reloadCached()
        #expect(model.entries.map(\.slug) == ["new", "a"])
    }

    /// Removals are marks, so an empty mirror is an unreadable one — never blank the page for it.
    @Test func anEmptyReadDoesNotBlankTheList() async {
        let model = WatchlistModel(cached: [film("a", 0, id: 1)],
                                   settings: LetterboxdSettings(username: "x"),
                                   reload: { [] },
                                   run: { _ in [] })
        await model.reloadCached()
        #expect(model.entries.map(\.slug) == ["a"])
    }

    @Test func withoutAReaderReloadChangesNothing() async {
        let model = WatchlistModel(cached: [film("a", 0, id: 1)],
                                   settings: LetterboxdSettings(username: "x"),
                                   run: { _ in [] })
        await model.reloadCached()
        #expect(model.entries.map(\.slug) == ["a"])
    }

    /// A reload landing mid-sync must not overwrite the crawl's answer with the older mirror.
    @Test func reloadDuringASyncIsIgnored() async {
        let gate = AsyncGate()
        let model = WatchlistModel(cached: [film("a", 0, id: 1)],
                                   settings: LetterboxdSettings(username: "x"),
                                   reload: { [film("stale", 0, id: 3)] },
                                   run: { _ in await gate.wait(); return [film("b", 0, id: 2)] })
        let sync = Task { await model.syncNow() }
        await until { if case .syncing = model.phase { true } else { false } }
        await model.reloadCached()
        #expect(model.entries.map(\.slug) == ["a"])
        await gate.open()
        await sync.value
        #expect(model.entries.map(\.slug) == ["b"])
    }

    @Test func previewSubjectForAWatchlistFilm() {
        let item = MediaItem(id: "movie:tmdb:7", kind: .movie, title: "Seven", year: 1995,
                             sources: [], seasons: [], tmdbID: 7, posterPath: "/p.jpg")
        let subject = PreviewSubject(item: item, overview: "Two detectives.", backdropPath: "/b.jpg",
                                     tags: ["In Library"], showsKind: false)
        #expect(subject.id == "movie:tmdb:7")
        #expect(subject.tmdbID == 7)
        #expect(subject.year == 1995)
        #expect(subject.overview == "Two detectives.")
        #expect(subject.backdropPath == "/b.jpg")
        #expect(subject.tags == ["In Library"])
        #expect(subject.showsKind == false)
        // Blank overviews read as none, as everywhere else.
        #expect(PreviewSubject(item: item, overview: "  ", backdropPath: nil, tags: [],
                               showsKind: false).overview == nil)
        // The other subjects keep their kind and carry no tags.
        #expect(PreviewSubject(item: item).showsKind)
        #expect(PreviewSubject(item: item).tags.isEmpty)
    }
}
