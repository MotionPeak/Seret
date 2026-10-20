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
    let started = AsyncCounter()
    let failing: Set<Int>

    init(gate: AsyncGate? = nil, failing: Set<Int> = []) {
        self.gate = gate
        self.failing = failing
    }

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
        if let gate { await gate.wait() }
        lock.withLock { _running -= 1 }
        if failing.contains(id) { throw URLError(.notConnectedToInternet) }
        return WatchlistFilmDetails(tmdbID: id, genres: ["Drama"], runtimeMinutes: 90 + id,
                                    voteAverage: 7, voteCount: 500, overview: "film \(id)",
                                    backdropPath: "/b\(id).jpg", logoPath: nil,
                                    fetchedAt: Date(timeIntervalSince1970: 1_000_000))
    }
}

private func tempFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wl-details-\(UUID().uuidString).json")
}

@MainActor
@Suite struct WatchlistDetailsStoreTests {

    private func store(_ fetcher: FakeFetcher, file: URL? = nil, now: Date = Date(timeIntervalSince1970: 1_000_000),
                       concurrency: Int = 6) -> WatchlistDetailsStore {
        WatchlistDetailsStore(fileURL: file, now: { now }, concurrency: concurrency,
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

        let later = Date(timeIntervalSince1970: 1_000_000 + 31 * 86_400)
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
        await store(fetcher, file: file, now: Date(timeIntervalSince1970: 1_000_000 + 29 * 86_400)).ensure([1])
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
