import DebridCore
import DebridUI
import Observation

/// The Detail screen's source of truth for one title. Renders instantly from the cached
/// `MediaItem`, then enriches on-demand from TMDB and loads watch state. Degrades silently
/// on failure (keeps base info), mirroring 7b-i's `LibraryStore`.
@MainActor
@Observable
final class DetailStore {
    enum RichState: Equatable { case idle, loading, loaded, failed }

    let item: MediaItem
    private let details: MediaDetailsProviding
    private let watch: WatchProgressProviding?

    private(set) var richState: RichState = .idle
    private(set) var backdropPath: String?
    private(set) var runtime: Int?
    private(set) var genres: [String] = []
    private(set) var overview: String?
    private(set) var selectedSeason: Int
    private(set) var episodeMeta: [Int: [Int: TMDBEpisodeDetails]] = [:]   // season → epNo → meta
    private(set) var watchByKey: [String: WatchState] = [:]                // contentKey → state

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        self.item = item
        self.details = details
        self.watch = watch
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        self.selectedSeason = item.seasons.first?.number ?? 1
    }

    // Movies: ranked sources.
    var versions: [MediaSource] { item.sources.bestFirst() }
    var bestSource: MediaSource? { item.sources.best }

    func load() async {
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
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                backdropPath = d.backdropPath ?? backdropPath
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                await loadSeason(selectedSeason, tvID: tmdbID)
            }
            richState = .loaded
        } catch {
            richState = .failed          // keep base info; no error wall
        }
    }

    func selectSeason(_ n: Int) async {
        selectedSeason = n
        await loadWatchForSeason(n)
        guard episodeMeta[n] == nil, let tvID = item.tmdbID else { return }
        await loadSeason(n, tvID: tvID)
    }

    func watchState(forKey key: String) -> WatchState? { watchByKey[key] }

    /// Mark a movie or episode watched/unwatched. `source` records the exact file (sourceKey).
    func setWatched(_ watched: Bool, contentKey: String, source: MediaSource) async {
        guard let watch else { return }
        // A manual mark has no playback position — `finished` drives the UI (full bar / ✓);
        // live playback progress (position) is written later by the 7c player.
        try? await watch.record(contentKey: contentKey, sourceKey: WatchKey.source(source),
                                positionSeconds: 0, durationSeconds: 0, finished: watched)
        await refreshWatch(contentKey)
    }

    /// Build a playback request for a movie source or an episode.
    func playRequest(source: MediaSource, episode: Episode?, label: String,
                     fromStart: Bool = false) -> PlaybackRequest {
        let key = episode.map { WatchKey.content(forShow: item, episode: $0) }
            ?? WatchKey.content(forMovie: item)
        let resume: Double? = fromStart ? nil : watchByKey[key].flatMap {
            (!$0.finished && $0.positionSeconds > 0) ? $0.positionSeconds : nil
        }
        return PlaybackRequest(item: item, source: source, resumeAt: resume, label: label, contentKey: key)
    }

    /// Best-effort "what to play next" for a show's hero: first in-progress episode (series
    /// order), else the first not-known-finished episode, else the very first. Uses whatever
    /// watch state is currently loaded.
    func nextEpisode() -> Episode? {
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
