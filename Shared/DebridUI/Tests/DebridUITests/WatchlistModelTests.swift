import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// File scope, not methods on the suite: the sync closure is `@Sendable` and runs off the main
/// actor, so a MainActor-isolated helper cannot be called from inside it.
private func entry(_ slug: String, position: Int, tmdbID: Int?) -> WatchlistEntry {
    // A matched entry carries the poster path TMDB returned alongside the id — the resolver sets
    // both together — so a fixture without one is not a shape the app ever stores.
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                   tmdbID: tmdbID, posterPath: tmdbID.map { "/\($0).jpg" }, resolvedAt: Date())
}

private func enabled(lastImport: Date?) -> LetterboxdSettings {
    LetterboxdSettings(username: "thebigshin", isEnabled: true, lastImportAt: lastImport)
}

/// A file-scope builder for the same reason `entry` is one: the sync and remove closures are
/// `@Sendable`, so what they capture has to be an immutable `let`.
private func removedEntry(_ slug: String, at when: Date) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: 0,
                   tmdbID: 1, posterPath: "/1.jpg", resolvedAt: Date(), removedAt: when)
}

@MainActor
@Suite struct WatchlistModelTests {

    @Test func syncReplacesTheEntriesAndEndsIdle() async {
        let model = WatchlistModel(cached: [], settings: enabled(lastImport: nil)) { progress in
            progress(1, 1)
            return [entry("speed", position: 0, tmdbID: 1637)]
        }
        await model.syncNow()
        #expect(model.entries.map(\.slug) == ["speed"])
        #expect(model.phase == .idle)
    }

    /// Stale data beats an empty screen: a failed sync keeps what was already there.
    @Test func aFailedSyncKeepsTheEntriesAndSaysWhy() async {
        let model = WatchlistModel(cached: [entry("old", position: 0, tmdbID: 1)],
                                   settings: enabled(lastImport: nil)) { _ in
            throw LetterboxdError.profileUnavailable
        }
        await model.syncNow()
        #expect(model.entries.map(\.slug) == ["old"])
        if case .failed(let message) = model.phase {
            #expect(message.lowercased().contains("private") || message.lowercased().contains("gone"))
        } else {
            Issue.record("expected .failed, got \(model.phase)")
        }
    }

    @Test func openingAgainStraightAwayDoesNotReCrawl() async {
        let ran = RanFlag()
        let justNow = Date()
        let model = WatchlistModel(cached: [entry("a", position: 0, tmdbID: 1)],
                                   settings: enabled(lastImport: justNow),
                                   minimumInterval: 600,
                                   now: { justNow.addingTimeInterval(60) }) { _ in
            ran.set(); return []
        }
        await model.syncIfStale()
        #expect(ran.value == false)
    }

    @Test func openingAfterTheIntervalDoesReCrawl() async {
        let ran = RanFlag()
        let then = Date()
        let model = WatchlistModel(cached: [], settings: enabled(lastImport: then),
                                   minimumInterval: 600,
                                   now: { then.addingTimeInterval(601) }) { _ in
            ran.set(); return []
        }
        await model.syncIfStale()
        #expect(ran.value == true)
    }

    @Test func aFirstEverOpenSyncs() async {
        let ran = RanFlag()
        let model = WatchlistModel(cached: [], settings: enabled(lastImport: nil)) { _ in
            ran.set(); return []
        }
        await model.syncIfStale()
        #expect(ran.value == true)
    }

    @Test func nothingRunsWithoutAUsername() async {
        let ran = RanFlag()
        let model = WatchlistModel(cached: [],
                                   settings: LetterboxdSettings(username: "", isEnabled: true)) { _ in
            ran.set(); return []
        }
        await model.syncNow()
        #expect(ran.value == false)
    }

    @Test func aFilmAlreadyInTheLibraryIsMarked() async {
        let model = WatchlistModel(cached: [entry("speed", position: 0, tmdbID: 1637),
                                            entry("heat", position: 1, tmdbID: 949)],
                                   settings: enabled(lastImport: nil)) { _ in [] }
        model.ownedTMDBIDs = [1637]
        #expect(model.isOwned(model.entries[0]))
        #expect(!model.isOwned(model.entries[1]))
    }

    /// An unresolved entry has no TMDB id, so it can never be "owned" — and must not crash asking.
    @Test func anUnresolvedEntryIsNeverOwned() async {
        let unresolved = WatchlistEntry(slug: "x", name: "X (1994)", year: 1994, position: 0)
        let model = WatchlistModel(cached: [unresolved], settings: enabled(lastImport: nil)) { _ in [] }
        model.ownedTMDBIDs = [1637]
        #expect(!model.isOwned(unresolved))
    }

    /// The tile goes at once, before the store is asked — a removal that waits on a disk write
    /// reads as a press that did nothing.
    @Test func removingHidesTheFilmImmediately() async {
        let model = WatchlistModel(cached: [entry("a", position: 0, tmdbID: 1),
                                            entry("b", position: 1, tmdbID: 2)],
                                   settings: enabled(lastImport: nil),
                                   remove: { _ in [] }) { _ in [] }

        await model.remove(entry("a", position: 0, tmdbID: 1))
        #expect(model.entries.map(\.slug) == ["b"])
        // Still in the mirror, marked — that is what survives the next crawl.
        #expect(model.allEntries.count == 2)
        #expect(model.allEntries.first(where: { $0.slug == "a" })?.isRemoved == true)
    }

    /// What the store says is what is true, since the store is what the next crawl merges into.
    @Test func theStoredMirrorWinsOverTheOptimisticEdit() async {
        let stored = removedEntry("a", at: Date(timeIntervalSince1970: 99))
        let model = WatchlistModel(cached: [entry("a", position: 0, tmdbID: 1)],
                                   settings: enabled(lastImport: nil),
                                   remove: { _ in [stored] }) { _ in [] }

        await model.remove(entry("a", position: 0, tmdbID: 1))
        #expect(model.allEntries[0].removedAt == Date(timeIntervalSince1970: 99))
        #expect(model.entries.isEmpty)
    }

    /// A sync must not resurrect what was removed — the reconciler carries the mark, and the
    /// model must keep filtering on it.
    @Test func aSyncDoesNotBringBackARemovedFilm() async {
        let removed = removedEntry("a", at: Date())
        let model = WatchlistModel(cached: [], settings: enabled(lastImport: nil)) { _ in
            [removed, entry("b", position: 1, tmdbID: 2)]
        }
        await model.syncNow()
        #expect(model.entries.map(\.slug) == ["b"])
    }

    @Test func spinningLandsOnSomethingOnTheWatchlist() async {
        let model = WatchlistModel(cached: (0..<5).map { entry("f\($0)", position: $0, tmdbID: $0 + 1) },
                                   settings: enabled(lastImport: nil)) { _ in [] }
        #expect(model.canSpin)
        let spin = model.spin()
        #expect(spin != nil)
        #expect(model.entries.contains { $0.slug == spin?.winner.slug })
    }

    /// Nothing eligible means the control should not be offered at all.
    @Test func anEmptyWatchlistCannotSpin() async {
        let model = WatchlistModel(cached: [], settings: enabled(lastImport: nil)) { _ in [] }
        #expect(model.canSpin == false)
        #expect(model.spin() == nil)
    }
}
