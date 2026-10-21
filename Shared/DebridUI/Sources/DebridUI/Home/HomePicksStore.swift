import Foundation
import Observation
import DebridCore

/// What `HomePicksStore` reads, as seams so tests run on fakes with no network, disk or SwiftData.
public struct HomePicksDependencies: Sendable {
    /// The owner's Letterboxd profile — the diary the picks follow.
    public var profile: any LetterboxdProfileReading
    public var taste: any LetterboxdTasteReading
    /// The two watchlist mirrors as they stand on disk. `partner` is nil with no partner set up.
    public var watchlists: @Sendable () async -> (owner: [WatchlistEntry], partner: [WatchlistEntry]?,
                                                  partnerName: String?)
    /// Which of these TMDB ids the device has finished.
    public var finishedTMDB: @Sendable (_ ids: [Int]) async -> Set<Int>
    /// TMDB genres for the watchlist films whose details are known.
    public var candidateGenres: @MainActor () -> [Int: [String]]
    public var cache: HomePicksCache

    public init(profile: any LetterboxdProfileReading,
                taste: any LetterboxdTasteReading,
                watchlists: @escaping @Sendable () async -> (owner: [WatchlistEntry],
                                                             partner: [WatchlistEntry]?,
                                                             partnerName: String?),
                finishedTMDB: @escaping @Sendable (_ ids: [Int]) async -> Set<Int>,
                candidateGenres: @escaping @MainActor () -> [Int: [String]],
                cache: HomePicksCache) {
        self.profile = profile
        self.taste = taste
        self.watchlists = watchlists
        self.finishedTMDB = finishedTMDB
        self.candidateGenres = candidateGenres
        self.cache = cache
    }
}

/// Home's two watchlist rows: "Picked for right now" and "Both of you want to see".
///
/// - **Instant.** `load()` publishes from the cached day's list and the watchlist mirrors already
///   on disk; it never waits on Letterboxd.
/// - **Once a day.** The picks are recomputed when the cached list is from an earlier local day,
///   in ONE store-owned task: a view whose `.task` goes away does not cancel it, and a second
///   caller joins it rather than starting another crawl.
/// - **Never an error.** A refresh that cannot read the diary keeps the last list (or, on a first
///   run, no row at all) and tries again no sooner than `retryAfter`.
/// - **Local watch state on every load**, not just at refresh: a film finished tonight leaves both
///   rows the next time Home shows, though the day's list was made this morning.
@MainActor
@Observable
public final class HomePicksStore {
    /// The longest the Both row gets.
    nonisolated public static let bothLimit = 30
    /// Picks kept beyond the row, so a film finished during the day leaves a full row behind.
    nonisolated static let storedPicks = WatchlistPicker.rowTarget + 10
    /// How long a failed refresh waits before Letterboxd is asked again.
    nonisolated static let retryAfter: TimeInterval = 15 * 60
    /// Directors are read for this many of the newest references.
    nonisolated static let directorReferences = 10
    /// The second hop reads the similar lists of this many top similar films of this many references.
    nonisolated static let secondHopReferences = 5
    nonisolated static let secondHopPerReference = 3

    /// The day's picks, minus anything finished here or taken off both watchlists. At most `rowTarget`.
    public private(set) var picked: [WatchlistEntry] = []
    /// Films on both lists, in the day's shuffle, minus anything finished here. At most `bothLimit`.
    public private(set) var both: [WatchlistEntry] = []
    /// Whose list each film is on. Nil with no partner.
    public private(set) var membership: WatchlistMembership?
    public private(set) var partnerName: String?

    @ObservationIgnored private let dependencies: HomePicksDependencies
    @ObservationIgnored private let now: @Sendable () -> Date
    /// The store is the cache's only writer, so once read, memory is the truth.
    @ObservationIgnored private var snapshot: HomePicksSnapshot?
    @ObservationIgnored private var cacheRead = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var failedAt: Date?
    /// Bumped by every publish, so a slow one cannot overwrite a newer one.
    @ObservationIgnored private var publishGeneration = 0

    public init(dependencies: HomePicksDependencies, now: @escaping @Sendable () -> Date = Date.init) {
        self.dependencies = dependencies
        self.now = now
    }

    /// The store, or nil when no Letterboxd username is set — "not configured", and Home then
    /// keeps its Recently Added rows.
    public static func make(settings: LetterboxdSettings,
                            now: @escaping @Sendable () -> Date = Date.init,
                            dependencies: (_ username: String) -> HomePicksDependencies) -> HomePicksStore? {
        let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return nil }
        return HomePicksStore(dependencies: dependencies(username), now: now)
    }

    /// The local calendar day, `yyyy-MM-dd`. The cache's key and the Both row's shuffle seed.
    public static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Publishes from the cache and the mirrors at once, then starts the day's refresh if it is due
    /// — without waiting for it.
    public func load() async {
        await readCacheOnce()
        await publish()
        startRefreshIfStale()
    }

    /// Recomputes the picks if the cached list is not from today, or joins the refresh already
    /// running. Returns when it has finished. Never throws.
    public func refreshIfStale() async {
        await readCacheOnce()
        startRefreshIfStale()
        await refreshTask?.value
    }

    // MARK: - Refresh

    private func readCacheOnce() async {
        guard !cacheRead else { return }
        let stored = await dependencies.cache.read()
        // A refresh may have landed during the read; never replace it with the older file.
        guard !cacheRead else { return }
        cacheRead = true
        if snapshot == nil { snapshot = stored }
    }

    private func startRefreshIfStale() {
        guard refreshTask == nil else { return }
        let date = now()
        let today = Self.day(of: date)
        guard snapshot?.day != today else { return }
        if let failedAt, date >= failedAt, date.timeIntervalSince(failedAt) < Self.retryAfter { return }

        let dependencies = dependencies
        let genres = dependencies.candidateGenres()
        refreshTask = Task { [weak self] in
            let picks = await Self.compute(dependencies, candidateGenres: genres)
            await self?.finishRefresh(picks, day: today)
        }
    }

    private func finishRefresh(_ picks: [WatchlistPick]?, day: String) async {
        if let picks {
            let fresh = HomePicksSnapshot(day: day, picks: picks)
            snapshot = fresh
            cacheRead = true
            failedAt = nil
            await dependencies.cache.write(fresh)
        } else {
            failedAt = now()
        }
        refreshTask = nil
        await publish()
    }

    /// The day's picks, read off Letterboxd. Nil when the diary cannot be read — the one request
    /// the list cannot do without. Any other page that fails is simply left out.
    ///
    /// Nonisolated, so the whole crawl runs off the main actor; only the result is published there.
    nonisolated static func compute(_ dependencies: HomePicksDependencies,
                                    candidateGenres: [Int: [String]]) async -> [WatchlistPick]? {
        let films: [LetterboxdEntry]
        do {
            films = try await dependencies.profile.films()
        } catch {
            return nil
        }

        let lists = await dependencies.watchlists()
        let candidates = WatchlistMerge.combine(owner: lists.owner, partner: lists.partner ?? [])
        let membership = lists.partner.map { WatchlistMembership(owner: lists.owner, partner: $0) }
        let watchedSlugs = Set(films.map(\.slug))
        let watchedTMDB = await dependencies.finishedTMDB(
            candidates.filter { !$0.isRemoved }.compactMap(\.tmdbID))

        let refs = WatchlistPicker.references(films)
        let refSlugs = Set(refs.map(\.slug))
        let eligible = Set(candidates.compactMap { entry -> String? in
            guard let tmdb = entry.tmdbID, !entry.isRemoved, !watchedSlugs.contains(entry.slug),
                  !watchedTMDB.contains(tmdb), !refSlugs.contains(entry.slug) else { return nil }
            return entry.slug
        })
        // Nothing to choose from: no point reading a single film page.
        guard !eligible.isEmpty, !refs.isEmpty else { return [] }

        let taste = dependencies.taste
        var similar: [String: [String]] = [:]
        var referenceGenres: [String: [String]] = [:]
        var directorsOf: [String: [String]] = [:]
        for ref in refs {
            if let list = try? await taste.similarFilms(to: ref.slug) {
                similar[ref.slug] = list.map(\.slug)
            }
            if let facts = try? await taste.filmPage(ref.slug) {
                referenceGenres[ref.slug] = facts.genres
                directorsOf[ref.slug] = facts.directorSlugs
            }
        }

        var byDirector: [String: [String]] = [:]
        var directorFilms: [String: [String]] = [:]
        for ref in refs.prefix(directorReferences) {
            var slugs: [String] = []
            for director in directorsOf[ref.slug] ?? [] {
                if byDirector[director] == nil {
                    // A failure is remembered as empty: the next reference by the same director
                    // should not ask again.
                    byDirector[director] = (try? await taste.films(byDirector: director))?.map(\.slug) ?? []
                }
                slugs += byDirector[director] ?? []
            }
            if !slugs.isEmpty { directorFilms[ref.slug] = slugs }
        }

        // Looser matches only when the close and director ones cannot fill the row.
        var secondHop: [String: [String]] = [:]
        let reached = Set(similar.values.joined()).union(directorFilms.values.joined())
        if eligible.intersection(reached).count < WatchlistPicker.rowTarget {
            var asked: Set<String> = []
            for ref in refs.prefix(secondHopReferences) {
                for slug in (similar[ref.slug] ?? []).prefix(secondHopPerReference)
                where asked.insert(slug).inserted {
                    if let list = try? await taste.similarFilms(to: slug) {
                        secondHop[slug] = list.map(\.slug)
                    }
                }
            }
        }

        let inputs = WatchlistPickInputs(recentFilms: films,
                                         similar: similar,
                                         secondHop: secondHop,
                                         directorFilms: directorFilms,
                                         referenceGenres: referenceGenres,
                                         candidates: candidates,
                                         membership: membership,
                                         candidateGenres: candidateGenres,
                                         watchedSlugs: watchedSlugs,
                                         watchedTMDB: watchedTMDB)
        return WatchlistPicker.pick(inputs, limit: storedPicks)
    }

    // MARK: - Publish

    /// Builds both rows from the current snapshot, the mirrors as they stand and the device's
    /// finished films.
    private func publish() async {
        publishGeneration += 1
        let generation = publishGeneration

        let lists = await dependencies.watchlists()
        let live = WatchlistMerge.combine(owner: lists.owner, partner: lists.partner ?? [])
            .filter { !$0.isRemoved }
        let membership = lists.partner.map { WatchlistMembership(owner: lists.owner, partner: $0) }
        let shared = membership.map { membership in
            live.filter { entry in
                guard entry.tmdbID != nil else { return false }
                let holders = membership.holders(of: entry)
                return holders.owner && holders.partner
            }
        } ?? []

        let picks = snapshot?.picks ?? []
        let ids = Set(picks.compactMap(\.entry.tmdbID) + shared.compactMap(\.tmdbID))
        let finished = ids.isEmpty ? [] : await dependencies.finishedTMDB(ids.sorted())
        // A newer publish started while this one waited: it has fresher inputs.
        guard generation == publishGeneration else { return }

        // A pick shows as the film's live row (its poster may have been filled in since), and
        // only while some list still holds it.
        let liveBySlug = Dictionary(live.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let liveByID = Dictionary(live.compactMap { entry in entry.tmdbID.map { ($0, entry) } },
                                  uniquingKeysWith: { first, _ in first })
        picked = Array(picks.lazy.compactMap { pick -> WatchlistEntry? in
            guard let entry = liveBySlug[pick.entry.slug] ?? pick.entry.tmdbID.flatMap({ liveByID[$0] }),
                  let tmdb = entry.tmdbID, !finished.contains(tmdb) else { return nil }
            return entry
        }.prefix(WatchlistPicker.rowTarget))

        // Shuffled from a fixed order (by slug, not list position — a film added to either list
        // renumbers every position) so the day's order only depends on which films are shared.
        var generator = SeededGenerator(seed: Self.day(of: now()))
        both = Array(shared.sorted { $0.slug < $1.slug }
            .shuffled(using: &generator)
            .filter { !finished.contains($0.tmdbID ?? -1) }
            .prefix(Self.bothLimit))
        self.membership = membership
        partnerName = membership == nil ? nil : lists.partnerName
    }
}
