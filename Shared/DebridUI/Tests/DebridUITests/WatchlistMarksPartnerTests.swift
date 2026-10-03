import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private struct NamedListReader: LetterboxdProfileReading {
    let films: [(slug: String, tmdb: Int)]
    func films() async throws -> [LetterboxdEntry] { [] }
    func watchlist() async throws -> [LetterboxdEntry] {
        films.map { LetterboxdEntry(slug: $0.slug, name: "\($0.slug) (1994)", year: 1994, rating: nil) }
    }
}

private struct TableResolver: WatchlistTitleResolving {
    let ids: [String: Int]
    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        ids[WatchlistName.stripYear(from: name)].map { WatchlistMatch(tmdbID: $0, posterPath: nil) }
    }
}

private func list(_ films: [(slug: String, tmdb: Int)]) -> WatchlistSyncer {
    WatchlistSyncer(reader: NamedListReader(films: films),
                    resolver: TableResolver(ids: Dictionary(uniqueKeysWithValues: films.map { ($0.slug, $0.tmdb) })),
                    store: WatchlistStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("marks-partner-\(UUID().uuidString).json")),
                    resolveDelay: .zero)
}

/// The real combined list under the toggle, so the wording is tested against what the mirrors
/// actually hold after the write — not against a fake's idea of it.
@MainActor
private func marks(owner: [(slug: String, tmdb: Int)],
                   partner: [(slug: String, tmdb: Int)]) async throws -> WatchlistMarks {
    let combined = CombinedWatchlist(owner: list(owner), partner: list(partner), partnerName: "Noga")
    _ = try await combined.sync(onProgress: nil)
    let sut = WatchlistMarks(
        entries: { await combined.cached() },
        add: { film in await combined.add(tmdbID: film.tmdbID, title: film.title, year: film.year,
                                          posterPath: film.posterPath) },
        remove: { slug in await combined.remove(slug: slug) },
        relay: { .idle },
        status: { await combined.status() })
    await sut.load()
    return sut
}

private func film(_ tmdb: Int) -> WatchlistFilm {
    WatchlistFilm(tmdbID: tmdb, title: "Film \(tmdb)", year: 1994, posterPath: nil)
}

@MainActor
@Suite struct WatchlistMarksPartnerTests {

    @Test func aPartnersFilmReadsAsOnTheWatchlist() async throws {
        let sut = try await marks(owner: [], partner: [("heat", 2)])
        #expect(sut.contains(tmdbID: 2))
    }

    /// Nothing is written to the partner's account, and the sentence must not claim otherwise.
    @Test func removingAPartnersFilmSaysItIsOnlyHiddenHere() async throws {
        let sut = try await marks(owner: [], partner: [("heat", 2)])
        await sut.toggle(film: film(2))
        #expect(!sut.contains(tmdbID: 2))
        #expect(sut.lastOutcome?.message == "Hidden in Seret — Noga's Letterboxd is unchanged")
        #expect(sut.lastOutcome?.isFailure == false)
    }

    @Test func removingASharedFilmSaysItStaysOnThePartners() async throws {
        let sut = try await marks(owner: [("dune", 3)], partner: [("dune", 3)])
        await sut.toggle(film: film(3))
        #expect(!sut.contains(tmdbID: 3))
        // No server in this test, so the owner's half is still waiting to go out.
        #expect(sut.lastOutcome?.message
                == "Removed from your watchlist — Letterboxd hasn't been told yet · still on Noga's")
    }

    @Test func removingTheOwnersOwnFilmIsWordedAsBefore() async throws {
        let sut = try await marks(owner: [("speed", 1)], partner: [("heat", 2)])
        await sut.toggle(film: film(1))
        #expect(sut.lastOutcome?.message == "Removed from your watchlist — Letterboxd hasn't been told yet")
    }

    /// Re-adding a partner's film hidden here is a real add to the owner's list — not the undo of
    /// a write that never existed, which would send nothing.
    @Test func reAddingAHiddenPartnersFilmIsARealAdd() async throws {
        let sut = try await marks(owner: [], partner: [("heat", 2)])
        await sut.toggle(film: film(2))
        await sut.toggle(film: film(2))
        #expect(sut.contains(tmdbID: 2))
        #expect(sut.lastOutcome?.message == "Added to your watchlist — Letterboxd hasn't been told yet")
    }

    /// Reading whose list a film is on is a suspension point, and a second press landing inside
    /// it must still be refused — or both removals run and the relay can post the same one twice.
    @Test func aSecondPressWhileTheStatusIsReadIsIgnored() async {
        let gate = StatusGate()
        let removals = RemovalCount()
        let row = WatchlistEntry(slug: "heat", name: "heat (1994)", year: 1994, position: 0,
                                 tmdbID: 2, resolvedAt: Date())
        let sut = WatchlistMarks(entries: { [row] }, add: { _ in [row] },
                                 remove: { _ in removals.bump(); return [] },
                                 relay: { .idle },
                                 status: { await gate.hold(); return .solo })
        await sut.load()

        async let first: Void = sut.toggle(film: film(2))
        await gate.waitForArrival()
        // A second press. With the guard in place it returns at once; without it, it reaches the
        // gate too and is released along with the first.
        let second = Task { await sut.toggle(film: film(2)) }
        for _ in 0..<20 { await Task.yield() }
        await gate.open()
        await first
        await second.value
        #expect(removals.value == 1)
    }
}

private actor StatusGate {
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

private final class RemovalCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
