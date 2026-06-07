import DebridCore
import Observation

/// The Detail screen's source of truth for one title. Renders instantly from the cached
/// `MediaItem`, then enriches on-demand from TMDB and loads watch state. Degrades silently
/// on failure (keeps base info), mirroring 7b-i's `LibraryStore`.
@MainActor
@Observable
public final class DetailStore {
    public enum RichState: Equatable { case idle, loading, loaded, failed }

    public let item: MediaItem
    private let details: MediaDetailsProviding
    private let watch: WatchProgressProviding?

    public private(set) var richState: RichState = .idle
    public private(set) var backdropPath: String?
    public private(set) var runtime: Int?
    public private(set) var genres: [String] = []
    public private(set) var overview: String?
    public private(set) var selectedSeason: Int
    public private(set) var episodeMeta: [Int: [Int: TMDBEpisodeDetails]] = [:]   // season → epNo → meta
    public private(set) var watchByKey: [String: WatchState] = [:]                // contentKey → state
    /// Set once TMDB details resolve — needed to grab a whole-season pack from the library page.
    public private(set) var imdbID: String?
    public private(set) var originalLanguage: String?
    /// TMDB's total season count (set once details resolve) — drives the all-seasons picker so the
    /// library page shows every season, not just the downloaded ones.
    public private(set) var numberOfSeasons: Int?

    public init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        self.item = item
        self.details = details
        self.watch = watch
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        self.selectedSeason = item.seasons.first?.number ?? 1
    }

    // Movies: ranked sources.
    public var versions: [MediaSource] { item.sources.bestFirst() }
    public var bestSource: MediaSource? { item.sources.best }

    /// Every season to show (TMDB's full count ∪ any owned seasons), sorted. Falls back to the owned
    /// seasons (or the selected one) until TMDB details resolve — so the picker lists ALL seasons,
    /// not just the downloaded ones.
    public var allSeasons: [Int] {
        var set = Set(item.seasons.map(\.number))
        if let n = numberOfSeasons, n > 0 { set.formUnion(1...n) }
        if set.isEmpty { set.insert(selectedSeason) }
        return set.sorted()
    }

    /// One row in a show's episode list: TMDB metadata plus the owned source when downloaded.
    public struct EpisodeRowInfo: Identifiable, Sendable {
        public let season: Int
        public let number: Int
        public let meta: TMDBEpisodeDetails?
        public let ownedSource: MediaSource?     // nil = not downloaded yet
        public var id: String { "s\(season)e\(number)" }
        public var isDownloaded: Bool { ownedSource != nil }
        /// The owned `Episode` (play / watch-key) when downloaded.
        public var ownedEpisode: Episode? {
            ownedSource.map { Episode(season: season, number: number, source: $0) }
        }
    }

    /// The full episode list for a season — every TMDB episode, merged with whatever is downloaded.
    /// Not-downloaded episodes still appear (`ownedSource == nil`) so the whole show is browsable.
    public func episodes(forSeason season: Int) -> [EpisodeRowInfo] {
        let owned = item.seasons.first { $0.number == season }?.episodes ?? []
        let ownedByNumber = Dictionary(owned.map { ($0.number, $0.source) }, uniquingKeysWith: { a, _ in a })
        let metas = episodeMeta[season] ?? [:]
        let numbers = Set(metas.keys).union(owned.map(\.number)).sorted()
        return numbers.map { n in
            EpisodeRowInfo(season: season, number: n, meta: metas[n], ownedSource: ownedByNumber[n])
        }
    }

    public func load() async {
        // Re-entrancy guard: one load per store (a retry after failure is still allowed).
        guard richState == .idle || richState == .failed else { return }
        richState = .loading
        await loadWatch()
        guard let tmdbID = item.tmdbID else { richState = .loaded; return }
        do {
            switch item.kind {
            case .movie:
                let d = try await details.movieDetails(tmdbID: tmdbID)
                backdropPath = d.backdropPath ?? backdropPath
                runtime = d.runtime
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                imdbID = d.imdbID
                originalLanguage = d.originalLanguage
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                backdropPath = d.backdropPath ?? backdropPath
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                imdbID = d.imdbID
                originalLanguage = d.originalLanguage
                numberOfSeasons = d.numberOfSeasons
                await loadSeason(selectedSeason, tvID: tmdbID)
            }
            richState = .loaded
        } catch {
            richState = .failed          // keep base info; no error wall
        }
    }

    public func selectSeason(_ n: Int) async {
        selectedSeason = n
        await loadWatchForSeason(n)
        guard episodeMeta[n] == nil, let tvID = item.tmdbID else { return }
        await loadSeason(n, tvID: tvID)
    }

    public func watchState(forKey key: String) -> WatchState? { watchByKey[key] }

    /// Mark a movie or episode watched/unwatched. `source` records the exact file (sourceKey).
    public func setWatched(_ watched: Bool, contentKey: String, source: MediaSource) async {
        guard let watch else { return }
        // A manual mark has no playback position — `finished` drives the UI (full bar / ✓);
        // live playback progress (position) is written later by the 7c player.
        try? await watch.record(contentKey: contentKey, sourceKey: WatchKey.source(source),
                                positionSeconds: 0, durationSeconds: 0, finished: watched)
        await refreshWatch(contentKey)
    }

    /// Build a playback request for a movie source or an episode.
    public func playRequest(source: MediaSource, episode: Episode?, label: String,
                     fromStart: Bool = false) -> PlaybackRequest {
        let key = episode.map { WatchKey.content(forShow: item, episode: $0) }
            ?? WatchKey.content(forMovie: item)
        let resume: Double? = fromStart ? nil : watchByKey[key].flatMap {
            (!$0.finished && $0.positionSeconds > 0) ? $0.positionSeconds : nil
        }
        return PlaybackRequest(item: item, source: source, resumeAt: resume, label: label,
                               contentKey: key, episode: episode)
    }

    /// Build a play request for an episode just downloaded from this page (its fresh `TorrentInfo`),
    /// keyed like the library's so progress lines up after the next refresh. nil if no video file.
    public func playRequest(forAdded info: TorrentInfo, season: Int, number: Int) -> PlaybackRequest? {
        guard let (file, link) = info.primaryVideoFile() else { return nil }
        let parsed = FilenameParser().parse(info.filename)
        let source = MediaSource(torrentID: info.id, fileID: file.id, restrictedLink: link, parsed: parsed)
        let episode = Episode(season: season, number: number, source: source)
        return playRequest(source: source, episode: episode,
                           label: "\(item.title) — S\(season)·E\(number)", fromStart: true)
    }

    /// Best-effort "what to play next" for a show's hero: first in-progress episode (series
    /// order), else the first not-known-finished episode, else the very first. Uses whatever
    /// watch state is currently loaded.
    public func nextEpisode() -> Episode? {
        let all = item.seasons.sorted { $0.number < $1.number }
            .flatMap { $0.episodes.sorted { $0.number < $1.number } }
        if let inProgress = all.first(where: {
            let w = watchByKey[WatchKey.content(forShow: item, episode: $0)]
            return w.map { !$0.finished && $0.positionSeconds > 0 } ?? false
        }) { return inProgress }
        if let unfinished = all.first(where: {
            watchByKey[WatchKey.content(forShow: item, episode: $0)]?.finished != true
        }) { return unfinished }
        return all.first
    }

    // MARK: - Private

    private func loadSeason(_ n: Int, tvID: Int) async {
        do {
            let eps = try await details.seasonEpisodes(tvID: tvID, season: n)
            episodeMeta[n] = Dictionary(eps.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // leave episodeMeta[n] nil → rows degrade to "Episode N"
        }
    }

    private func loadWatch() async {
        switch item.kind {
        case .movie: await refreshWatch(WatchKey.content(forMovie: item))
        case .show:  await loadWatchForSeason(selectedSeason)
        }
    }

    private func loadWatchForSeason(_ n: Int) async {
        guard let season = item.seasons.first(where: { $0.number == n }) else { return }
        for ep in season.episodes {
            await refreshWatch(WatchKey.content(forShow: item, episode: ep))
        }
    }

    private func refreshWatch(_ key: String) async {
        guard let watch else { return }
        watchByKey[key] = try? await watch.progress(forContentKey: key)
    }
}
