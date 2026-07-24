import DebridCore
import Foundation

/// The subset of TraktClient the provider needs — a seam so tests use a fake, not the network.
public protocol TraktWatchAPI: Sendable {
    func playbackMovies() async throws -> [TraktPlaybackItem]
    func playbackEpisodes() async throws -> [TraktPlaybackItem]
    func watchedMovies() async throws -> [TraktWatchedMovie]
    func watchedShows() async throws -> [TraktWatchedShow]
    func ratedMovies() async throws -> [TraktRatingItem]
    func ratedEpisodes() async throws -> [TraktRatingItem]
    func ratedShows() async throws -> [TraktRatingItem]
    func addToHistory(_ refs: [TraktMediaRef]) async throws
    func removeFromHistory(_ refs: [TraktMediaRef]) async throws
    func scrobble(_ action: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws
}

extension TraktClient: TraktWatchAPI {}

/// Trakt-backed watch state. Conforms to `WatchProgressProviding` so all existing readers work
/// unchanged. Holds an in-memory cache (no disk persistence); `refresh()` rebuilds it from Trakt.
public actor TraktWatchProvider: WatchProgressProviding {
    private let api: TraktWatchAPI

    // cache: contentKey -> paused fraction (0…1) + pausedAt
    private var playback: [String: (fraction: Double, pausedAt: Date)] = [:]
    private var order: [String] = []              // contentKeys, newest pausedAt first
    private var watchedKeys: Set<String> = []
    private var ratings: [String: Int] = [:]      // contentKey -> 1…10
    /// Whether the cache has been filled from Trakt at least once, plus the in-flight fill. Reads
    /// lazily warm the cache instead of returning an empty answer: the sign-in refresh is
    /// fire-and-forget, so a screen opened before it lands would otherwise see "no rating" /
    /// "no progress" and never re-read (the bug where a rating vanished on relaunch).
    private var loaded = false
    private var loadTask: Task<Void, Never>?
    // Actor-isolated (ISO8601DateFormatter isn't Sendable, so it can't be a shared static).
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(api: TraktWatchAPI) {
        self.api = api
    }

    /// Content key for a Trakt playback/watched/rating item, matching the enricher's id scheme.
    private static func key(movie: TraktMovieRef?) -> String? {
        movie?.ids.tmdb.map { TraktMapping.movieContentKey(tmdb: $0) }
    }
    private static func key(show: TraktShowRef?, episode: TraktEpisodeRef?) -> String? {
        guard let show = show?.ids.tmdb, let ep = episode else { return nil }
        return TraktMapping.episodeContentKey(showTmdb: show, season: ep.season, number: ep.number)
    }
    private static func key(for item: TraktPlaybackItem) -> String? {
        key(movie: item.movie) ?? key(show: item.show, episode: item.episode)
    }

    // MARK: Cache rebuild

    public func refresh() async throws {
        async let movies = api.playbackMovies()
        async let episodes = api.playbackEpisodes()
        async let wMovies = api.watchedMovies()
        async let wShows = api.watchedShows()
        async let rMovies = api.ratedMovies()
        async let rEpisodes = api.ratedEpisodes()
        async let rShows = api.ratedShows()

        var pb: [String: (Double, Date)] = [:]
        for item in try await movies + (try await episodes) {
            guard let k = Self.key(for: item) else { continue }
            let at = iso.date(from: item.pausedAt) ?? .distantPast
            pb[k] = (item.progress / 100.0, at)
        }
        playback = pb.mapValues { (fraction: $0.0, pausedAt: $0.1) }
        order = pb.sorted { $0.value.1 > $1.value.1 }.map(\.key)

        var watched: Set<String> = []
        for m in try await wMovies { if let k = Self.key(movie: m.movie) { watched.insert(k) } }
        for s in try await wShows {
            guard let show = s.show.ids.tmdb else { continue }
            for season in s.seasons {
                for ep in season.episodes {
                    watched.insert(TraktMapping.episodeContentKey(showTmdb: show, season: season.number, number: ep.number))
                }
            }
        }
        watchedKeys = watched

        var rate: [String: Int] = [:]
        for r in try await rMovies { if let k = Self.key(movie: r.movie) { rate[k] = r.rating } }
        for r in try await rEpisodes { if let k = Self.key(show: r.show, episode: r.episode) { rate[k] = r.rating } }
        // Show-level ratings key off the series itself ("show:tmdb:…"), not an episode.
        for r in try await rShows {
            if let tmdb = r.show?.ids.tmdb { rate[TraktMapping.showContentKey(tmdb: tmdb)] = r.rating }
        }
        ratings = rate
        loaded = true
    }

    /// Fill the cache once if nothing has yet, coalescing concurrent callers onto one fetch. A
    /// failure leaves `loaded` false so the next read retries rather than caching an empty answer.
    private func ensureLoaded() async {
        if loaded { return }
        if let task = loadTask { await task.value; return }
        let task = Task { _ = try? await self.refresh() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Fraction (0…1) for a paused key, for the player to convert to seconds via its known duration.
    public func fraction(forContentKey key: String) async -> Double? {
        await ensureLoaded()
        return playback[key]?.fraction
    }

    /// This user's 1…10 Trakt rating for a title, if any.
    public func rating(forContentKey key: String) async -> Int? {
        await ensureLoaded()
        return ratings[key]
    }

    /// Set (or clear with nil) this user's Trakt rating and update the cache.
    public func setRating(_ value: Int?, forContentKey key: String) async {
        guard let ref = TraktMapping.ref(forContentKey: key) else { return }
        if let value {
            try? await (api as? TraktRatingWriting)?.rate(ref, rating: value)
            ratings[key] = value
        } else {
            try? await (api as? TraktRatingWriting)?.removeRating(ref)
            ratings[key] = nil
        }
    }

    // MARK: WatchProgressProviding

    public func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
        await ensureLoaded()
        if watchedKeys.contains(key) {
            return WatchState(contentKey: key, sourceKey: "", positionSeconds: 0,
                              durationSeconds: 0, finished: true, updatedAt: .distantPast)
        }
        guard let pb = playback[key] else { return nil }
        return WatchState(contentKey: key, sourceKey: "", positionSeconds: 0, durationSeconds: 0,
                          finished: false, updatedAt: pb.pausedAt)
    }

    public func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        var out: [String: WatchState] = [:]
        for k in keys { out[k] = try await progress(forContentKey: k, profileID: profileID) }
        return out
    }

    public func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                       durationSeconds: Double, finished: Bool, profileID: String) async throws {
        // Live position writes go through TraktScrobbler, not here. This path serves the manual
        // Mark Watched/Unwatched actions (DetailStore/LibraryStore call record with position 0).
        guard let ref = TraktMapping.ref(forContentKey: contentKey) else { return }
        if finished {
            try await api.addToHistory([ref])
            watchedKeys.insert(contentKey)
        } else if positionSeconds == 0 {          // explicit "mark unwatched"
            try await api.removeFromHistory([ref])
            watchedKeys.remove(contentKey)
        }
    }

    public func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        await ensureLoaded()
        return order.prefix(limit).compactMap { k in
            guard let pb = playback[k] else { return nil }
            return WatchState(contentKey: k, sourceKey: "", positionSeconds: 0, durationSeconds: 0,
                              finished: false, updatedAt: pb.pausedAt)
        }
    }

    public func deleteProgress(forContentKeys keys: [String]) async throws {
        for k in keys { playback[k] = nil; watchedKeys.remove(k); ratings[k] = nil }
        order.removeAll { keys.contains($0) }
    }
}

/// Rating writes — split out so the `TraktWatchAPI` seam (used for reads/history) stays focused;
/// the concrete `TraktClient` conforms to both.
public protocol TraktRatingWriting: Sendable {
    func rate(_ ref: TraktMediaRef, rating: Int) async throws
    func removeRating(_ ref: TraktMediaRef) async throws
}

extension TraktClient: TraktRatingWriting {}
