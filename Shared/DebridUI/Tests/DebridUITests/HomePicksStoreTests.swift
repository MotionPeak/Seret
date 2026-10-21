import Testing
import Foundation
@testable import DebridUI
import DebridCore

// MARK: - Fakes

private actor FakeProfile: LetterboxdProfileReading {
    private let result: Result<[LetterboxdEntry], LetterboxdError>
    private(set) var calls = 0

    init(_ films: [LetterboxdEntry]) { result = .success(films) }
    init(failing error: LetterboxdError) { result = .failure(error) }

    func films() async throws -> [LetterboxdEntry] {
        calls += 1
        return try result.get()
    }
    func watchlist() async throws -> [LetterboxdEntry] { [] }
}

private actor FakeTaste: LetterboxdTasteReading {
    private let similar: [String: [String]]
    private let facts: [String: LetterboxdFilmFacts]
    private let directors: [String: [String]]
    /// Slugs whose similar page fails, to prove one bad page does not sink the refresh.
    private let failingSimilar: Set<String>
    private(set) var similarAsked: [String] = []
    private(set) var calls = 0

    init(similar: [String: [String]] = [:], facts: [String: LetterboxdFilmFacts] = [:],
         directors: [String: [String]] = [:], failingSimilar: Set<String> = []) {
        self.similar = similar
        self.facts = facts
        self.directors = directors
        self.failingSimilar = failingSimilar
    }

    func similarFilms(to slug: String) async throws -> [LetterboxdEntry] {
        calls += 1
        similarAsked.append(slug)
        if failingSimilar.contains(slug) { throw LetterboxdError.profileUnavailable }
        return (similar[slug] ?? []).map { LetterboxdEntry(slug: $0, name: $0, year: nil, rating: nil) }
    }
    func filmPage(_ slug: String) async throws -> LetterboxdFilmFacts {
        calls += 1
        return facts[slug] ?? LetterboxdFilmFacts(directorSlugs: [], genres: [])
    }
    func films(byDirector slug: String) async throws -> [LetterboxdEntry] {
        calls += 1
        return (directors[slug] ?? []).map { LetterboxdEntry(slug: $0, name: $0, year: nil, rating: nil) }
    }
}

/// What the device has finished, changeable between loads.
private actor FakeFinished {
    var ids: Set<Int> = []
    func set(_ ids: Set<Int>) { self.ids = ids }
}

@MainActor
@Suite struct HomePicksStoreTests {
    /// Noon, so "yesterday" and "tomorrow" are a whole day away in any time zone.
    private static let today = Date(timeIntervalSince1970: 1_761_048_000)
    private static let yesterday = today.addingTimeInterval(-86_400)
    private static let tomorrow = today.addingTimeInterval(86_400)

    private static func film(_ slug: String, _ tmdb: Int, position: Int = 0, year: Int? = 2000) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: slug, year: year, position: position, tmdbID: tmdb)
    }
    private static let collateral = film("collateral", 1, position: 0)
    private static let thief = film("thief", 2, position: 1)

    private static func pick(_ entry: WatchlistEntry, _ score: Double = 1) -> WatchlistPick {
        WatchlistPick(entry: entry, score: score, tier: .close)
    }

    private static func cache() -> HomePicksCache {
        HomePicksCache(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "home-picks-\(UUID().uuidString).json"))
    }

    private static func store(profile: FakeProfile = FakeProfile([]),
                              taste: FakeTaste = FakeTaste(),
                              owner: [WatchlistEntry] = [collateral, thief],
                              partner: [WatchlistEntry]? = nil,
                              partnerName: String? = nil,
                              finished: FakeFinished = FakeFinished(),
                              cache: HomePicksCache,
                              now: Date = today) -> HomePicksStore {
        let deps = HomePicksDependencies(
            profile: profile,
            taste: taste,
            watchlists: { (owner, partner, partnerName) },
            finishedTMDB: { ids in await finished.ids.intersection(ids) },
            candidateGenres: { [:] },
            cache: cache)
        return HomePicksStore(dependencies: deps, now: { now })
    }

    private static func day(_ date: Date) -> String { HomePicksStore.day(of: date) }

    // MARK: - The cache

    @Test func loadPublishesTheCachedPicksAtOnce() async {
        let cache = Self.cache()
        await cache.write(HomePicksSnapshot(day: Self.day(Self.today), picks: [Self.pick(Self.thief)]))
        let profile = FakeProfile([])
        let taste = FakeTaste()
        let store = Self.store(profile: profile, taste: taste, cache: cache)

        await store.load()
        #expect(store.picked.map(\.slug) == ["thief"])

        await store.refreshIfStale()
        #expect(await profile.calls == 0)
        #expect(await taste.calls == 0)
    }

    @Test func aStaleCacheIsRecomputedOncePerDay() async {
        let cache = Self.cache()
        await cache.write(HomePicksSnapshot(day: Self.day(Self.yesterday), picks: [Self.pick(Self.thief)]))
        let profile = FakeProfile([LetterboxdEntry(slug: "heat", name: "Heat", year: 1995, rating: 9)])
        let taste = FakeTaste(similar: ["heat": ["collateral"]])
        let store = Self.store(profile: profile, taste: taste, cache: cache)

        await store.load()
        #expect(store.picked.map(\.slug) == ["thief"])        // yesterday's, instantly
        await store.refreshIfStale()

        #expect(await profile.calls == 1)
        #expect(store.picked.map(\.slug) == ["collateral"])
        let written = await cache.read()
        #expect(written?.day == Self.day(Self.today))
        #expect(written?.picks.map(\.entry.slug) == ["collateral"])

        // The same day again: no Letterboxd at all.
        await store.load()
        await store.refreshIfStale()
        #expect(await profile.calls == 1)

        // A fresh store on the same device the same day reads the file, not Letterboxd.
        let again = Self.store(profile: profile, taste: taste, cache: cache)
        await again.load()
        await again.refreshIfStale()
        #expect(await profile.calls == 1)
        #expect(again.picked.map(\.slug) == ["collateral"])
    }

    @Test func aFailedRefreshKeepsTheCachedPicks() async {
        let cache = Self.cache()
        let old = HomePicksSnapshot(day: Self.day(Self.yesterday), picks: [Self.pick(Self.thief)])
        await cache.write(old)
        let profile = FakeProfile(failing: .profileUnavailable)
        let store = Self.store(profile: profile, cache: cache)

        await store.load()
        await store.refreshIfStale()

        #expect(await profile.calls == 1)
        #expect(store.picked.map(\.slug) == ["thief"])
        #expect(await cache.read() == old)
    }

    @Test func aFirstRunFailureLeavesNoPickedRow() async {
        let profile = FakeProfile(failing: .profileUnavailable)
        let store = Self.store(profile: profile, cache: Self.cache())

        await store.load()
        await store.refreshIfStale()

        #expect(await profile.calls == 1)
        #expect(store.picked.isEmpty)
    }

    /// Home refreshes after every film; a Letterboxd outage must not mean a crawl attempt each time.
    @Test func aFailedRefreshIsNotRetriedAtOnce() async {
        let profile = FakeProfile(failing: .profileUnavailable)
        let store = Self.store(profile: profile, cache: Self.cache())

        await store.load()
        await store.refreshIfStale()
        await store.load()
        await store.refreshIfStale()

        #expect(await profile.calls == 1)
    }

    @Test func oneFailingPageIsSkippedNotFatal() async {
        let profile = FakeProfile([LetterboxdEntry(slug: "heat", name: "Heat", year: 1995, rating: 9),
                                   LetterboxdEntry(slug: "ronin", name: "Ronin", year: 1998, rating: 8)])
        let taste = FakeTaste(similar: ["heat": ["collateral"], "ronin": ["thief"]],
                              failingSimilar: ["heat"])
        let store = Self.store(profile: profile, taste: taste, cache: Self.cache())

        await store.load()
        await store.refreshIfStale()

        #expect(store.picked.map(\.slug) == ["thief"])
    }

    @Test func theSecondHopRunsOnlyWhenTheCloseMatchesAreFew() async {
        let profile = FakeProfile([LetterboxdEntry(slug: "heat", name: "Heat", year: 1995, rating: 9)])
        let taste = FakeTaste(similar: ["heat": ["ronin"], "ronin": ["thief"]])
        let store = Self.store(profile: profile, taste: taste, cache: Self.cache())

        await store.load()
        await store.refreshIfStale()

        #expect(await taste.similarAsked == ["heat", "ronin"])
        #expect(store.picked.map(\.slug) == ["thief"])

        // Enough close matches: no second hop.
        let many = (0..<WatchlistPicker.rowTarget).map { Self.film("f\($0)", 100 + $0, position: $0) }
        let fullTaste = FakeTaste(similar: ["heat": many.map(\.slug)])
        let full = Self.store(profile: profile, taste: fullTaste, owner: many, cache: Self.cache())
        await full.load()
        await full.refreshIfStale()
        #expect(await fullTaste.similarAsked == ["heat"])
        #expect(full.picked.count == WatchlistPicker.rowTarget)
    }

    // MARK: - Local watch state

    @Test func aFilmFinishedLocallyDropsOutOfBothRows() async {
        let cache = Self.cache()
        await cache.write(HomePicksSnapshot(day: Self.day(Self.today),
                                            picks: [Self.pick(Self.collateral, 2), Self.pick(Self.thief)]))
        let finished = FakeFinished()
        let store = Self.store(partner: [Self.collateral, Self.thief], partnerName: "Noga",
                               finished: finished, cache: cache)

        await store.load()
        #expect(store.picked.map(\.slug) == ["collateral", "thief"])
        #expect(Set(store.both.map(\.slug)) == ["collateral", "thief"])

        // Finished today, after the day's list was made: gone on the next load.
        await finished.set([1])
        await store.load()
        #expect(store.picked.map(\.slug) == ["thief"])
        #expect(store.both.map(\.slug) == ["thief"])
    }

    @Test func aPickTakenOffTheWatchlistsLeavesTheRow() async {
        let cache = Self.cache()
        await cache.write(HomePicksSnapshot(day: Self.day(Self.today),
                                            picks: [Self.pick(Self.collateral, 2), Self.pick(Self.thief)]))
        var removed = Self.collateral
        removed.removedAt = Self.today
        let store = Self.store(owner: [removed, Self.thief], cache: cache)

        await store.load()
        #expect(store.picked.map(\.slug) == ["thief"])
    }

    // MARK: - Both of you want to see

    @Test func noPartnerMeansNoBothRow() async {
        let store = Self.store(owner: [Self.collateral, Self.thief], partner: nil, cache: Self.cache())

        await store.load()

        #expect(store.both.isEmpty)
        #expect(store.membership == nil)
        #expect(store.partnerName == nil)
    }

    @Test func theBothRowHoldsOnlyFilmsOnBothLists() async {
        let onlyMine = Self.film("onlymine", 9, position: 2)
        let onlyHers = Self.film("onlyhers", 10, position: 0)
        var hidden = Self.film("hidden", 11, position: 3)
        hidden.removedAt = Self.today
        let unmatched = WatchlistEntry(slug: "nomatch", name: "nomatch", year: nil, position: 4)
        let store = Self.store(owner: [Self.collateral, Self.thief, onlyMine, hidden, unmatched],
                               partner: [Self.thief, onlyHers, hidden, unmatched], partnerName: "Noga",
                               cache: Self.cache())

        await store.load()

        #expect(store.both.map(\.slug) == ["thief"])
        #expect(store.membership != nil)
        #expect(store.partnerName == "Noga")
    }

    @Test func theBothRowIsStableAllDayAndChangesTheNextDay() async {
        let shared = (0..<8).map { Self.film("shared\($0)", 200 + $0, position: $0) }
        func order(on date: Date) async -> [String] {
            let store = Self.store(owner: shared, partner: shared, partnerName: "Noga",
                                   cache: Self.cache(), now: date)
            await store.load()
            return store.both.map(\.slug)
        }

        let morning = await order(on: Self.today)
        let evening = await order(on: Self.today.addingTimeInterval(3_600))
        let nextDay = await order(on: Self.tomorrow)

        #expect(Set(morning) == Set(shared.map(\.slug)))
        #expect(morning == evening)
        #expect(Set(nextDay) == Set(morning))
        #expect(nextDay != morning)
        #expect(morning != shared.map(\.slug))        // shuffled, not the list's own order
    }

    @Test func theDailySeedIsTheSameInEveryProcess() {
        // Pinned values: a seed from `hashValue` would differ per launch and fail this.
        var a = SeededGenerator(seed: "2026-10-21")
        var b = SeededGenerator(seed: "2026-10-21")
        #expect(a.next() == b.next())
        #expect(SeededGenerator.stableHash("2026-10-21") == SeededGenerator.stableHash("2026-10-21"))
        #expect(SeededGenerator.stableHash("") == 0xcbf2_9ce4_8422_2325)       // FNV-1a offset basis
        #expect(SeededGenerator.stableHash("a") == 0xaf63_dc4c_8601_ec8c)      // FNV-1a("a")
    }

    // MARK: - Not configured

    @Test func noUsernameMeansNotConfigured() {
        var built: [String] = []
        let deps = { (username: String) -> HomePicksDependencies in
            built.append(username)
            return HomePicksDependencies(profile: FakeProfile([]), taste: FakeTaste(),
                                         watchlists: { ([], nil, nil) }, finishedTMDB: { _ in [] },
                                         candidateGenres: { [:] }, cache: Self.cache())
        }

        #expect(HomePicksStore.make(settings: LetterboxdSettings(username: ""), dependencies: deps) == nil)
        #expect(HomePicksStore.make(settings: LetterboxdSettings(username: "   "), dependencies: deps) == nil)
        #expect(built.isEmpty)

        #expect(HomePicksStore.make(settings: LetterboxdSettings(username: " thebigshin "),
                                    dependencies: deps) != nil)
        #expect(built == ["thebigshin"])
    }
}
