import DebridCore
import Observation

/// Orchestrates the full Add flow for one picked search result: resolve its TMDB details
/// (imdb_id + original_language), fork movie vs. show, own a per-target `AddStore` (the
/// stream-load + rank + add engine), and build the `PlaybackRequest` for Add & Play.
///
/// Movies resolve straight to a loaded `AddStore`. Shows expose seasons/episodes and build
/// a fresh `AddStore` for the episode the user picks (Comet queries are per `series(s,e)`).
@MainActor
@Observable
public final class AddFlowStore {
    public enum Phase: Equatable { case resolving, movie, show, resolveFailed(String) }

    public private(set) var phase: Phase = .resolving

    // Display metadata (set once details resolve).
    public private(set) var title: String = ""
    public private(set) var year: Int?
    public private(set) var posterPath: String?
    public private(set) var backdropPath: String?
    public private(set) var overview: String?

    // Show-only.
    public private(set) var seasons: [Int] = []
    public private(set) var selectedSeason: Int?
    public private(set) var episodes: [TMDBEpisodeDetails] = []
    public private(set) var selectedEpisode: Int?

    /// The stream/add engine for the current target (the movie, or the selected episode).
    public private(set) var add: AddStore?

    /// The whole-season download engine for the selected season (shows only) — grabs the best
    /// full-season pack so every episode is cached at once. nil until a season is selected.
    public private(set) var seasonAdd: AddStore?

    private let hit: SearchHit
    private let details: MediaDetailsProviding
    private let streamSource: StreamSource
    private let addService: AddProviding

    private var imdbID: String?
    private var originalLanguage: String?

    /// The chosen title's TMDB id + kind (for trailers / lookups).
    public var tmdbID: Int { hit.result.id }
    public var mediaKind: MediaKind { hit.kind }

    public init(hit: SearchHit, details: MediaDetailsProviding,
                streamSource: StreamSource, add: AddProviding) {
        self.hit = hit; self.details = details
        self.streamSource = streamSource; self.addService = add
    }

    public func resolve() async {
        phase = .resolving
        do {
            switch hit.kind {
            case .movie: try await resolveMovie()
            case .show:  try await resolveShow()
            }
        } catch {
            phase = .resolveFailed("Couldn't load this title. Check your connection and try again.")
        }
    }

    private func resolveMovie() async throws {
        let d = try await details.movieDetails(tmdbID: hit.result.id)
        guard let imdb = d.imdbID else {
            phase = .resolveFailed("No matching release found for this title.")
            return
        }
        title = d.title
        year = yearFrom(d.releaseDate)
        posterPath = d.posterPath ?? hit.result.posterPath
        backdropPath = d.backdropPath
        overview = d.overview
        imdbID = imdb
        originalLanguage = d.originalLanguage
        let store = makeAddStore(kind: .movie)
        add = store
        phase = .movie
        await store.loadStreams()
    }

    private func resolveShow() async throws {
        let d = try await details.tvDetails(tmdbID: hit.result.id)
        guard let imdb = d.imdbID else {
            phase = .resolveFailed("No matching release found for this title.")
            return
        }
        title = d.name
        year = yearFrom(d.firstAirDate)
        posterPath = d.posterPath ?? hit.result.posterPath
        backdropPath = d.backdropPath
        overview = d.overview
        imdbID = imdb
        originalLanguage = d.originalLanguage
        let n = d.numberOfSeasons ?? 0
        seasons = n > 0 ? Array(1...n) : []
        phase = .show
        if let first = seasons.first { await selectSeason(first) }
    }

    /// Load a season's episodes; clears any in-flight episode selection. Also spins up the
    /// whole-season download engine and starts finding the best full-season pack in the background.
    ///
    /// Re-entrant by design: the tvOS season pills switch on FOCUS, so gliding across them fires
    /// overlapping calls. Episodes clear immediately (the row shows skeletons, not the old
    /// season's cards), and a fetch that comes back after a newer pick was made is discarded —
    /// otherwise whichever season's TMDB response landed LAST won, regardless of the selection.
    public func selectSeason(_ season: Int) async {
        selectedSeason = season
        selectedEpisode = nil
        add = nil
        episodes = []
        let pack = makeAddStore(kind: .series(season: season, episode: 1), seasonPack: season)
        seasonAdd = pack
        let fetched = (try? await details.seasonEpisodes(tvID: hit.result.id, season: season)) ?? []
        guard selectedSeason == season else { return }   // superseded mid-flight → discard
        episodes = fetched
        await pack.loadStreams()
    }

    /// Download the whole selected season (the best cached full-season pack). After it lands the
    /// caller refreshes the library so every episode appears.
    public func addSeason() async { await seasonAdd?.addBest() }

    /// Pick an episode → build its `AddStore` and load cached streams.
    public func selectEpisode(_ episode: Int) async {
        guard let season = selectedSeason else { return }
        selectedEpisode = episode
        let store = makeAddStore(kind: .series(season: season, episode: episode))
        add = store
        await store.loadStreams()
    }

    public func addBest() async { await add?.addBest() }
    public func add(stream: CachedStream) async { await add?.add(stream: stream) }

    /// Ranked uncached candidates for the current movie/episode target (input to a request-download).
    public func uncachedCandidates() async -> [CachedStream] { await add?.uncachedCandidates() ?? [] }

    /// Try to play a picked version instantly: returns a `PlaybackRequest` if RD already has it
    /// cached, else nil (the caller then starts a download). No-op without a loaded `AddStore`.
    public func instantPlay(_ stream: CachedStream) async -> PlaybackRequest? {
        guard let info = await add?.tryInstantAdd(stream) else { return nil }
        return playbackRequest(from: info)
    }

    /// Build a `PlaybackRequest` from a freshly-added torrent for the Add & Play path.
    /// Returns nil if the torrent has no playable video file.
    public func playbackRequest(from info: TorrentInfo) -> PlaybackRequest? {
        guard let (file, link) = info.primaryVideoFile() else { return nil }
        let parsed = FilenameParser().parse(info.filename)
        let source = MediaSource(torrentID: info.id, fileID: file.id,
                                 restrictedLink: link, parsed: parsed)
        let itemKind: MediaKind = hit.kind
        let label: String
        let contentKey: String
        if case .show = itemKind, let s = selectedSeason, let e = selectedEpisode {
            label = "\(title) — S\(s)·E\(e)"
            contentKey = "tmdb:\(hit.result.id):s\(s)e\(e)"
        } else {
            label = title
            contentKey = "tmdb:\(hit.result.id)"
        }
        let item = MediaItem(id: contentKey, kind: itemKind, title: title, year: year,
                             sources: [source], seasons: [], tmdbID: hit.result.id,
                             posterPath: posterPath, backdropPath: backdropPath, overview: overview)
        return PlaybackRequest(item: item, source: source, resumeAt: nil,
                               label: label, contentKey: contentKey)
    }

    /// Only called after `resolve()` has set `imdbID` (it guards on a non-nil imdb_id before
    /// reaching `.movie`/`.show`), so the `?? ""` is just totality insurance.
    private func makeAddStore(kind: StreamQuery.Kind, seasonPack: Int? = nil) -> AddStore {
        AddStore(imdbID: imdbID ?? "", kind: kind, originalLanguage: originalLanguage,
                 streamSource: streamSource, add: addService, seasonPack: seasonPack,
                 title: title, year: year)
    }

    private func yearFrom(_ date: String?) -> Int? {
        guard let prefix = date?.prefix(4) else { return nil }
        return Int(prefix)
    }
}
