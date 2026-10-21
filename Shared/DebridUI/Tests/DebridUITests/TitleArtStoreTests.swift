import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// Counts calls; `gate` (when set) holds every call open until released.
private final class GatedDetails: MediaDetailsProviding, @unchecked Sendable {
    let entered = AsyncCounter()
    private let lock = NSLock()
    private var _calls: [Int] = []
    var calls: [Int] { lock.withLock { _calls } }
    nonisolated(unsafe) var gate: AsyncGate?
    nonisolated(unsafe) var failuresRemaining = 0
    struct Boom: Error {}

    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        let shouldFail: Bool = lock.withLock {
            _calls.append(tmdbID)
            let fail = failuresRemaining > 0
            if fail { failuresRemaining -= 1 }
            return fail
        }
        await entered.increment()
        if let gate { await gate.wait() }
        // A fetch whose own task was cancelled must fail, so a caller's cancellation leaking into
        // the shared fetch is observable.
        try Task.checkCancellation()
        if shouldFail { throw Boom() }
        let images = TMDBImageSet(backdrops: [TMDBImageRef(filePath: "/clean\(tmdbID).jpg", languageCode: nil)],
                                  logos: [TMDBImageRef(filePath: "/logo\(tmdbID).png", languageCode: "en")])
        return TMDBMovieDetails(id: tmdbID, title: "M\(tmdbID)", releaseDate: nil, overview: nil,
                                posterPath: nil, backdropPath: "/plain\(tmdbID).jpg", runtime: 120,
                                genres: [TMDBGenre(id: 1, name: "Drama"), TMDBGenre(id: 2, name: "Crime")],
                                voteAverage: 7.5, images: images)
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        lock.withLock { _calls.append(tmdbID) }
        return TMDBTVDetails(id: tmdbID, name: "S\(tmdbID)", firstAirDate: nil, overview: nil,
                             posterPath: nil, backdropPath: "/tvb.jpg", numberOfSeasons: 4,
                             genres: [TMDBGenre(id: 3, name: "Sci-Fi")], voteAverage: 8.1)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

@Suite struct TitleArtStoreTests {
    /// A header that read one title's art must not re-render when another title's art lands —
    /// the kept-alive pages behind Home re-rendered on every title Home's banner loaded.
    @MainActor @Test func anotherTitleLandingDoesNotInvalidateAReader() async {
        let store = TitleArtStore(details: GatedDetails())
        _ = await store.load(.movie, tmdbID: 1)
        let fired = Flag()
        withObservationTracking { _ = store.art(for: .movie, tmdbID: 1) } onChange: { fired.set() }
        _ = await store.load(.movie, tmdbID: 2)
        store.seed(TitleArt(logoPath: nil, backdropPath: nil, voteAverage: nil, genres: [],
                            runtimeMinutes: nil, seasonCount: nil), for: .movie, tmdbID: 3)
        #expect(!fired.value)
    }

    /// …but a reader waiting on a title still hears its art arrive.
    @MainActor @Test func aTitleLandingInvalidatesItsOwnReader() async {
        let store = TitleArtStore(details: GatedDetails())
        let fired = Flag()
        withObservationTracking { _ = store.art(for: .movie, tmdbID: 5) } onChange: { fired.set() }
        _ = await store.load(.movie, tmdbID: 5)
        #expect(fired.value)
        #expect(store.art(for: .movie, tmdbID: 5)?.logoPath == "/logo5.png")
    }

    @MainActor @Test func concurrentLoadsShareOneFetch() async {
        let fake = GatedDetails()
        let gate = AsyncGate()
        fake.gate = gate
        let store = TitleArtStore(details: fake)

        let first = Task { await store.load(.movie, tmdbID: 7) }
        await fake.entered.wait(atLeast: 1)          // the fetch is in flight
        let second = Task { await store.load(.movie, tmdbID: 7) }
        await settle()                               // second has joined the in-flight fetch
        #expect(fake.calls == [7])
        await gate.open()

        let a = await first.value, b = await second.value
        #expect(fake.calls == [7])
        #expect(a != nil)
        #expect(a == b)
    }

    @MainActor @Test func artCarriesLogoGenresRuntimeAndPreferredBackdrop() async {
        let store = TitleArtStore(details: GatedDetails())
        let art = await store.load(.movie, tmdbID: 7)
        #expect(art?.logoPath == "/logo7.png")
        #expect(art?.backdropPath == "/clean7.jpg")
        #expect(art?.genres == ["Drama", "Crime"])
        #expect(art?.runtimeMinutes == 120)
        #expect(art?.voteAverage == 7.5)
        #expect(art?.seasonCount == nil)
    }

    @MainActor @Test func showArtCarriesSeasonCount() async {
        let store = TitleArtStore(details: GatedDetails())
        let art = await store.load(.show, tmdbID: 3)
        #expect(art?.seasonCount == 4)
        #expect(art?.runtimeMinutes == nil)
        #expect(art?.genres == ["Sci-Fi"])
        #expect(art?.backdropPath == "/tvb.jpg")
    }

    @MainActor @Test func aFailureIsNilAndALaterLoadRetries() async {
        let fake = GatedDetails()
        fake.failuresRemaining = 1
        let store = TitleArtStore(details: fake)
        #expect(await store.load(.movie, tmdbID: 7) == nil)
        #expect(store.art(for: .movie, tmdbID: 7) == nil)
        let retry = await store.load(.movie, tmdbID: 7)
        #expect(retry?.logoPath == "/logo7.png")
        #expect(fake.calls == [7, 7])
    }

    @MainActor @Test func artIsReadableSynchronouslyOnceLoaded() async {
        let fake = GatedDetails()
        let store = TitleArtStore(details: fake)
        #expect(store.art(for: .movie, tmdbID: 7) == nil)
        let loaded = await store.load(.movie, tmdbID: 7)
        #expect(store.art(for: .movie, tmdbID: 7) == loaded)
        _ = await store.load(.movie, tmdbID: 7)
        #expect(fake.calls == [7])                   // second load served from cache
    }

    @MainActor @Test func kindIsPartOfTheKey() async {
        let fake = GatedDetails()
        let store = TitleArtStore(details: fake)
        _ = await store.load(.movie, tmdbID: 3)
        #expect(store.art(for: .show, tmdbID: 3) == nil)
    }

    @MainActor @Test func theOldestEntryIsEvictedAtCapacity() async {
        let fake = GatedDetails()
        let store = TitleArtStore(details: fake, capacity: 2)
        _ = await store.load(.movie, tmdbID: 1)
        _ = await store.load(.movie, tmdbID: 2)
        _ = await store.load(.movie, tmdbID: 3)      // evicts 1
        #expect(store.art(for: .movie, tmdbID: 1) == nil)
        #expect(store.art(for: .movie, tmdbID: 2) != nil)
        #expect(store.art(for: .movie, tmdbID: 3) != nil)
        _ = await store.load(.movie, tmdbID: 1)
        #expect(fake.calls == [1, 2, 3, 1])
    }

    @MainActor @Test func aRecentlyReadEntrySurvivesEviction() async {
        let fake = GatedDetails()
        let store = TitleArtStore(details: fake, capacity: 2)
        _ = await store.load(.movie, tmdbID: 1)
        _ = await store.load(.movie, tmdbID: 2)
        _ = await store.load(.movie, tmdbID: 1)      // touch 1 → 2 is now the oldest
        _ = await store.load(.movie, tmdbID: 3)
        #expect(store.art(for: .movie, tmdbID: 1) != nil)
        #expect(store.art(for: .movie, tmdbID: 2) == nil)
    }

    @MainActor @Test func aCancelledCallerDoesNotCancelTheSharedFetch() async {
        let fake = GatedDetails()
        let gate = AsyncGate()
        fake.gate = gate
        let store = TitleArtStore(details: fake)
        let first = Task { await store.load(.movie, tmdbID: 7) }
        await fake.entered.wait(atLeast: 1)
        let second = Task { await store.load(.movie, tmdbID: 7) }
        await settle()
        first.cancel()
        await gate.open()
        #expect(await second.value?.logoPath == "/logo7.png")
        #expect(store.art(for: .movie, tmdbID: 7) != nil)
        #expect(fake.calls == [7])
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
