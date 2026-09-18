import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// File scope, not methods on the suite: the sync closure is `@Sendable` and runs off the main
/// actor, so a MainActor-isolated helper cannot be called from inside it.
private func entry(_ slug: String, position: Int, tmdbID: Int?) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                   tmdbID: tmdbID, resolvedAt: Date())
}

private func enabled(lastImport: Date?) -> LetterboxdSettings {
    LetterboxdSettings(username: "thebigshin", isEnabled: true, lastImportAt: lastImport)
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
}
