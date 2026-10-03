import Testing
import Foundation
@testable import DebridCore

private struct SlugListReader: LetterboxdProfileReading {
    let slugs: [String]
    func films() async throws -> [LetterboxdEntry] { [] }
    func watchlist() async throws -> [LetterboxdEntry] {
        slugs.map { LetterboxdEntry(slug: $0, name: "\($0) (1994)", year: 1994, rating: nil) }
    }
}

/// Holds the FIRST TMDB search until the test opens it — the window in which the syncer actor is
/// suspended mid-sync and its other methods can run.
private actor ResolveGate {
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func hold() async {
        if opened { return }
        arrived = true
        arrival?.resume(); arrival = nil
        await withCheckedContinuation { waiting.append($0) }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func open() {
        opened = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

private struct GatedResolver: WatchlistTitleResolving {
    let gate: ResolveGate
    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        await gate.hold()
        let slug = WatchlistName.stripYear(from: name)
        return WatchlistMatch(tmdbID: slug.count * 1000 + Int(slug.unicodeScalars.first!.value),
                              posterPath: nil)
    }
}

/// A sync spends most of its time awaiting TMDB, one film at a time, and the syncer is an actor —
/// so the owner's own edits land in the middle of it. It used to save the snapshot it took before
/// those awaits, and every such edit was silently thrown away.
@Suite struct WatchlistSyncerConcurrencyTests {

    private func make(_ slugs: [String], seed: [WatchlistEntry] = []) -> (WatchlistSyncer, ResolveGate, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wl-concurrency-\(UUID().uuidString).json")
        let store = WatchlistStore(fileURL: url)
        store.save(seed)
        let gate = ResolveGate()
        return (WatchlistSyncer(reader: SlugListReader(slugs: slugs),
                                resolver: GatedResolver(gate: gate),
                                store: store, resolveDelay: .zero), gate, url)
    }

    /// Already matched, so this film is on the list before the sync and needs no search.
    private func known(_ slug: String, tmdb: Int, position: Int) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                       tmdbID: tmdb, resolvedAt: Date())
    }

    @Test func aRemovalMadeMidSyncSurvivesIt() async throws {
        let (syncer, gate, url) = make(["speed", "new"], seed: [known("speed", tmdb: 1637, position: 0)])
        defer { try? FileManager.default.removeItem(at: url) }

        async let synced = syncer.sync()
        await gate.waitForArrival()
        await syncer.remove(slug: "speed")
        await gate.open()
        _ = try await synced

        let stored = WatchlistStore(fileURL: url).load()
        #expect(stored.first { $0.slug == "speed" }?.isRemoved == true)
        // The sync's own work is kept too.
        #expect(stored.first { $0.slug == "new" }?.tmdbID != nil)
    }

    @Test func anAddMadeMidSyncSurvivesIt() async throws {
        let (syncer, gate, url) = make(["new"])
        defer { try? FileManager.default.removeItem(at: url) }

        async let synced = syncer.sync()
        await gate.waitForArrival()
        await syncer.add(tmdbID: 42, title: "Added", year: 2026, posterPath: nil)
        await gate.open()
        let result = try await synced

        let stored = WatchlistStore(fileURL: url).load()
        #expect(stored.contains { $0.tmdbID == 42 && $0.needsAddPush })
        #expect(result.contains { $0.tmdbID == 42 })
    }

    /// A push landing mid-sync: losing the mark would make the removal pending again and send it
    /// a second time.
    @Test func aPushRecordedMidSyncSurvivesIt() async throws {
        var removed = known("speed", tmdb: 1637, position: 0)
        removed.removedAt = Date()
        let (syncer, gate, url) = make(["speed", "new"], seed: [removed])
        defer { try? FileManager.default.removeItem(at: url) }

        async let synced = syncer.sync()
        await gate.waitForArrival()
        await syncer.markRemovalPushed(slug: "speed")
        await gate.open()
        _ = try await synced

        #expect(await syncer.pendingRemovals().isEmpty)
    }

    /// Taking back an add that never reached Letterboxd deletes its row outright. The sync carried
    /// that row (a crawl cannot contain a film never sent) and must not put it back.
    @Test func anUnsentAddTakenBackMidSyncStaysGone() async throws {
        let add = WatchlistEntry.locallyAdded(tmdbID: 9, title: "Mine", year: 2026,
                                              posterPath: nil, position: -1)
        let (syncer, gate, url) = make(["new"], seed: [add])
        defer { try? FileManager.default.removeItem(at: url) }

        async let synced = syncer.sync()
        await gate.waitForArrival()
        await syncer.remove(slug: add.slug)
        await gate.open()
        let result = try await synced

        #expect(!WatchlistStore(fileURL: url).load().contains { $0.tmdbID == 9 })
        #expect(!result.contains { $0.tmdbID == 9 })
    }
}
