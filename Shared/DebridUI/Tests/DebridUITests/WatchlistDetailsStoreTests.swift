import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// A details fetch that records what it was asked, can be held at a gate, and fails on request.
private final class FakeFetcher: @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [Int] = []
    private var _running = 0
    private var _maxRunning = 0
    let gate: AsyncGate?
    /// Only these ids wait at the gate; nil = every id does.
    let gated: Set<Int>?
    let started = AsyncCounter()
    private var _failing: Set<Int>

    init(gate: AsyncGate? = nil, gated: Set<Int>? = nil, failing: Set<Int> = []) {
        self.gate = gate
        self.gated = gated
        self._failing = failing
    }

    func heal() { lock.withLock { _failing = [] } }

    var asked: [Int] { lock.withLock { _asked } }
    var maxRunning: Int { lock.withLock { _maxRunning } }
    var running: Int { lock.withLock { _running } }

    func fetch(_ id: Int) async throws -> WatchlistFilmDetails {
        lock.withLock {
            _asked.append(id)
            _running += 1
            _maxRunning = max(_maxRunning, _running)
        }
        await started.increment()
        if let gate, gated?.contains(id) ?? true { await gate.wait() }
        let fails = lock.withLock { _running -= 1; return _failing.contains(id) }
        if fails { throw URLError(.notConnectedToInternet) }
        return WatchlistFilmDetails(tmdbID: id, genres: ["Drama"], runtimeMinutes: 90 + id,
                                    voteAverage: 7, voteCount: 500, overview: "film \(id)",
                                    backdropPath: "/b\(id).jpg", logoPath: nil,
                                    fetchedAt: Date(timeIntervalSince1970: 1_000_000))
    }
}

/// A clock a test can move.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wl-details-\(UUID().uuidString).json")
}

@MainActor
@Suite struct WatchlistDetailsStoreTests {

    private func store(_ fetcher: FakeFetcher, file: URL? = nil, now: Date = Date(timeIntervalSince1970: 1_000_000),
                       concurrency: Int = 6, publishEvery: Int = 24,
                       grace: Duration = .seconds(3600)) -> WatchlistDetailsStore {
        WatchlistDetailsStore(fileURL: file, now: { now }, concurrency: concurrency,
                              publishEvery: publishEvery, stragglerGrace: grace,
                              fetch: { try await fetcher.fetch($0) })
    }

    @Test func fetchesWhatIsMissingAndPublishesIt() async {
        let fetcher = FakeFetcher()
        let s = store(fetcher)
        await s.ensure([1, 2, 3])
        #expect(Set(fetcher.asked) == [1, 2, 3])
        #expect(s.details[2]?.overview == "film 2")
        #expect(s.details.count == 3)
    }

    @Test func persistsSoTheNextVisitIsInstant() async {
        let file = tempFile()
        let first = FakeFetcher()
        await store(first, file: file).ensure([1, 2])

        let second = FakeFetcher()
        let reopened = store(second, file: file)
        // Read from disk at init — before any fetch.
        #expect(reopened.details[1]?.runtimeMinutes == 91)
        await reopened.ensure([1, 2])
        #expect(second.asked.isEmpty)
    }

    @Test func refetchesEntriesOlderThanThirtyDaysButShowsThemMeanwhile() async {
        let file = tempFile()
        await store(FakeFetcher(), file: file, now: Date(timeIntervalSince1970: 1_000_000)).ensure([1])

        let later = Date(timeIntervalSince1970: 1_000_000 + 36 * 86_400)   // past 30 days + any jitter
        let fetcher = FakeFetcher()
        let s = store(fetcher, file: file, now: later)
        #expect(s.details[1] != nil)             // the stale copy is on screen before the refetch
        await s.ensure([1])
        #expect(fetcher.asked == [1])
        #expect(s.details[1] != nil)
    }

    @Test func freshEntriesAreNotRefetched() async {
        let file = tempFile()
        await store(FakeFetcher(), file: file, now: Date(timeIntervalSince1970: 1_000_000)).ensure([1])
        let fetcher = FakeFetcher()
        await store(fetcher, file: file, now: Date(timeIntervalSince1970: 1_000_000 + 24 * 86_400)).ensure([1])   // under 30 days - any jitter
        #expect(fetcher.asked.isEmpty)
    }

    @Test func neverRunsMoreThanTheCapAtOnce() async {
        let gate = AsyncGate()
        let fetcher = FakeFetcher(gate: gate)
        let s = store(fetcher, concurrency: 6)
        let load = Task { await s.ensure(Array(1...20)) }
        await fetcher.started.wait(atLeast: 6)
        await settle(200)
        #expect(fetcher.running == 6)
        await gate.open()
        await load.value
        #expect(fetcher.maxRunning == 6)
        #expect(fetcher.asked.count == 20)
        #expect(s.details.count == 20)
    }

    @Test func overlappingAsksShareOneFetchPerFilm() async {
        let gate = AsyncGate()
        let fetcher = FakeFetcher(gate: gate)
        let s = store(fetcher)
        let first = Task { await s.ensure([1, 2]) }
        await fetcher.started.wait(atLeast: 2)
        let second = Task { await s.ensure([2, 3]) }
        await settle()
        await gate.open()
        await first.value
        await second.value
        #expect(fetcher.asked.sorted() == [1, 2, 3])
        #expect(s.details.count == 3)
    }

    @Test func aFailedFilmDoesNotSinkTheOthers() async {
        let fetcher = FakeFetcher(failing: [2])
        let s = store(fetcher)
        await s.ensure([1, 2, 3])
        #expect(s.details[2] == nil)
        #expect(s.details[1] != nil && s.details[3] != nil)
        // Not hammered again this session.
        await s.ensure([2])
        #expect(fetcher.asked.filter { $0 == 2 }.count == 1)
    }

    /// Rows are built from `settled`: a first visit's batches fill the header's `details` as they
    /// land, but the rows only change once the pass is over — nothing re-sorts under focus.
    @Test func rowsWaitForThePassToSettle() async {
        let gate = AsyncGate()
        let fetcher = FakeFetcher(gate: gate, gated: [3])
        let s = store(fetcher, publishEvery: 1)
        func rows() -> [String] {
            let entries = (1...3).map {
                WatchlistEntry(slug: "f\($0)", name: "f\($0) (2000)", year: 2000, position: $0,
                               tmdbID: $0, posterPath: nil, resolvedAt: Date())
            }
            return WatchlistRows.build(entries: entries, details: s.settled, isOwned: { _ in false },
                                       membership: nil, partnerName: nil)
                .map { "\($0.id):\($0.entries.map(\.slug))" }
        }
        let before = rows()
        let load = Task { await s.ensure([1, 2, 3]) }
        await until { s.details.count == 2 }      // two batches published for the header…
        #expect(s.settled.isEmpty)                // …but not for the rows
        #expect(rows() == before)
        await gate.open()
        await load.value
        #expect(s.settled.count == 3)
        #expect(rows() != before)                 // the genre and short rows arrive, at once
    }

    /// One hung request must not hold the rows back for ever.
    @Test func aStragglerDoesNotHoldTheRowsBack() async {
        let gate = AsyncGate()
        let fetcher = FakeFetcher(gate: gate, gated: [3])
        // One at a time, so 1 and 2 have landed when 3 — the last — is dispatched and hangs.
        let s = store(fetcher, concurrency: 1, publishEvery: 1, grace: .zero)
        let load = Task { await s.ensure([1, 2, 3]) }
        await until { s.settled.count == 2 }
        #expect(s.settled[3] == nil)
        await gate.open()
        await load.value
        #expect(s.settled.count == 3)
    }

    @Test func generationCountsPublishes() async {
        let s = store(FakeFetcher(), publishEvery: 2)
        #expect(s.generation == 0)
        await s.ensure([1, 2, 3, 4])
        #expect(s.generation == 2)
    }

    /// A failure is retried — not straight away, but by an `ensure` after the cool-off.
    @Test func aFailedFilmIsRetriedAfterTheCoolOff() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let fetcher = FakeFetcher(failing: [2])
        let s = WatchlistDetailsStore(fileURL: nil, now: { clock.now }, retryAfter: 15 * 60,
                                      fetch: { try await fetcher.fetch($0) })
        await s.ensure([1, 2])
        fetcher.heal()
        clock.advance(10 * 60)
        await s.ensure([1, 2])
        #expect(fetcher.asked.filter { $0 == 2 }.count == 1)    // still cooling off
        clock.advance(6 * 60)
        await s.ensure([1, 2])
        #expect(fetcher.asked.filter { $0 == 2 }.count == 2)
        #expect(s.details[2] != nil)
        #expect(fetcher.asked.filter { $0 == 1 }.count == 1)    // a success is never re-asked
    }

    /// Films fetched together must not all go stale on the same day.
    @Test func staleAgeIsJitteredPerFilm() {
        let shifts = (1...200).map(WatchlistDetailsStore.ageJitter(for:))
        #expect(shifts.allSatisfy { abs($0) <= WatchlistDetailsStore.ageJitter })
        #expect(Set(shifts).count >= 5)
        #expect(WatchlistDetailsStore.ageJitter(for: 42) == WatchlistDetailsStore.ageJitter(for: 42))
    }

    @Test func aCallerGoingAwayDoesNotCancelTheLoad() async {
        let gate = AsyncGate()
        let fetcher = FakeFetcher(gate: gate)
        let s = store(fetcher)
        let asker = Task { await s.ensure([1, 2]) }
        await fetcher.started.wait(atLeast: 2)
        asker.cancel()
        await gate.open()
        await until { s.details.count == 2 }
    }

    @Test func seedsTheArtStoreForInstantHeaders() async {
        let art = TitleArtStore(details: NoDetails())
        let d = WatchlistFilmDetails(tmdbID: 9, genres: ["Horror"], runtimeMinutes: 89, voteAverage: 7.3,
                                     voteCount: 900, overview: nil, backdropPath: "/b.jpg",
                                     logoPath: "/l.png", fetchedAt: Date())
        art.seed(d.titleArt, for: .movie, tmdbID: 9)
        #expect(art.art(for: .movie, tmdbID: 9)?.logoPath == "/l.png")
        // A seed never overwrites what the store fetched itself.
        art.seed(TitleArt(logoPath: nil, backdropPath: nil, voteAverage: nil, genres: [],
                          runtimeMinutes: nil, seasonCount: nil), for: .movie, tmdbID: 9)
        #expect(art.art(for: .movie, tmdbID: 9)?.logoPath == "/l.png")
    }
}

private struct NoDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw URLError(.badURL) }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw URLError(.badURL) }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}
