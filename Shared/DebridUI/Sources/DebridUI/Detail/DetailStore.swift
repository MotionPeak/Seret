import DebridCore
import Foundation
import Observation

/// The Detail screen's source of truth for one title. Renders instantly from the cached
/// `MediaItem`, then enriches on-demand from TMDB and loads watch state. Degrades silently
/// on failure (keeps base info), mirroring 7b-i's `LibraryStore`.
@MainActor
@Observable
public final class DetailStore {
    public enum RichState: Equatable { case idle, loading, loaded, failed }

    /// The title this page is about. Replaced only by `adopt(_:)`, when the library gains it.
    public private(set) var item: MediaItem
    private let details: MediaDetailsProviding
    private let watch: WatchProgressProviding?
    /// The active profile whose progress this Detail reads/writes. nil → no active profile yet
    /// (record/read are skipped until `AppSession` sets one).
    private let profileID: String?
    private let myList: MyListProviding?
    /// Whether the active profile has this title in its My List (drives the Add/In-My-List button).
    public private(set) var inMyList = false
    private let ratingsProvider: RatingsProviding?
    private let letterboxdProvider: LetterboxdRatingProviding?
    private let subtitleEvidence: SubtitleEvidenceProviding?
    /// Hebrew subtitles OpenSubtitles has for this film. nil until asked, or when nothing is known.
    public private(set) var hebrewResults: [SubtitleResult]?
    /// Everything the rankers and the version badges know about subtitles.
    public private(set) var subtitles: SubtitleEvidenceSet = .empty

    public private(set) var richState: RichState = .idle
    public private(set) var backdropPath: String?
    public private(set) var logoPath: String?
    public private(set) var runtime: Int?
    public private(set) var genres: [String] = []
    public private(set) var overview: String?
    public private(set) var selectedSeason: Int
    public private(set) var episodeMeta: [Int: [Int: TMDBEpisodeDetails]] = [:]   // season → epNo → meta
    /// Seasons whose TMDB episode list could not be fetched. See `episodesState(forSeason:)`.
    private var failedSeasons: Set<Int> = []
    public private(set) var watchByKey: [String: WatchState] = [:]                // contentKey → state
    /// Set once TMDB details resolve — needed to grab a whole-season pack from the library page.
    public private(set) var imdbID: String?
    public private(set) var originalLanguage: String?
    /// TMDB's total season count (set once details resolve) — drives the all-seasons picker so the
    /// library page shows every season, not just the downloaded ones.
    public private(set) var numberOfSeasons: Int?

    /// External ratings (IMDb / Rotten Tomatoes / Metacritic) from OMDb — supplemental, loaded
    /// after TMDB details resolve. nil until loaded (or if unavailable).
    public private(set) var ratings: OMDbRatings?
    public private(set) var ratingsState: RichState = .idle

    /// Letterboxd's community score, on its own 0.5–5 scale. Films only — Letterboxd has no shows,
    /// so a show leaves this nil and never spends a request finding that out.
    public private(set) var letterboxdRating: LetterboxdFilmRating?
    public private(set) var letterboxdState: RichState = .idle

    /// Rich title-page fields. Cast / director / creators / similar ride along with the TMDB
    /// details call (`append_to_response`), so they cost no extra request.
    public private(set) var cast: [TMDBCastMember] = []
    public private(set) var director: String?
    /// The same directors, with their TMDB ids — what a pressable director control navigates with.
    /// `director` stays the printable form.
    public private(set) var directors: [TMDBPersonRef] = []
    public private(set) var creators: [String] = []
    /// A show's creators, with ids. Same relationship to `creators` as `directors` has to `director`.
    public private(set) var creatorRefs: [TMDBPersonRef] = []
    public private(set) var similar: [TMDBSearchResult] = []
    /// The franchise this film belongs to, once resolved. Movies only — TMDB has no collection
    /// concept for television. Nil when the film is standalone or the fetch failed.
    public private(set) var franchise: Franchise?
    /// The collection reference from the details call, held so the franchise fetch has an id.
    private var collectionRef: TMDBCollectionRef?
    /// The viewer's history rollup for this title, loaded lazily by the view.
    private let versionPrefs: VersionPreferring?
    /// The user's chosen source key for this title, once loaded. Nil = let the ranker decide.
    public private(set) var preferredSourceKey: String?
    /// Versions deleted from Real-Debrid while this screen was open — see `ownedSources`.
    private var removedSourceKeys: Set<String> = []

    public private(set) var watchSummary: WatchSummary?
    public private(set) var historySince: Date?

    public init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
                profileID: String? = nil, myList: MyListProviding? = nil,
                ratings: RatingsProviding? = nil, versionPrefs: VersionPreferring? = nil,
                letterboxd: LetterboxdRatingProviding? = nil,
                subtitleEvidence: SubtitleEvidenceProviding? = nil) {
        self.item = item
        self.details = details
        self.watch = watch
        self.profileID = profileID
        self.myList = myList
        self.ratingsProvider = ratings
        self.letterboxdProvider = letterboxd
        self.subtitleEvidence = subtitleEvidence
        self.versionPrefs = versionPrefs
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        // Viewing order, so a show that owns only its Specials plus season 1 does not open on
        // the extras — `item.seasons` is built in that order, but this must not depend on it.
        self.selectedSeason = item.seasons.sortedBySeason().first?.number ?? 1
    }

    // Movies: ranked sources.
    public var versions: [MediaSource] { ownedSources.bestFirst(subtitles: subtitles) }

    /// The versions still on Real-Debrid. `item` is an immutable snapshot taken when the screen
    /// opened, so a version deleted from here has to be filtered out locally — otherwise the row
    /// stays on screen (and Play could pick it) until the next library refresh.
    private var ownedSources: [MediaSource] {
        removedSourceKeys.isEmpty
            ? item.sources
            : item.sources.filter { !removedSourceKeys.contains(WatchKey.source($0)) }
    }

    /// The version Play uses: the user's choice when it still resolves to an owned source,
    /// otherwise the quality ranker. A preference for a torrent since deleted from RD must fall
    /// back rather than leave Play permanently broken.
    public var bestSource: MediaSource? { ownedSources.preferred(preferredSourceKey, subtitles: subtitles) }

    /// The hero's Hebrew chip: about the version Play will use when you own one, about the film
    /// otherwise. nil hides it.
    public var hebrewChip: HebrewTitleChip? {
        HebrewTitleChip.forTitle(playing: bestSource, subtitles: subtitles, hebrewResults: hebrewResults)
    }

    /// The Hebrew level of one owned copy, for its row's badge.
    public func hebrew(for source: MediaSource) -> HebrewSubtitles {
        subtitles.hebrew(forVersion: WatchKey.source(source))
    }

    /// The film's original language, named for the meta line. nil leaves it off.
    public var languageName: String? { LanguageName.forTitle(originalLanguage) }

    /// The page is about files you own: a film with a version, or a show with an episode. A
    /// placeholder (a title not added yet, a Watchlist entry) has neither — and nothing to remove.
    public var isInLibrary: Bool { !item.sources.isEmpty || !item.seasons.isEmpty }

    /// The library now holds this title — take its item, files and all.
    ///
    /// The page used to keep the snapshot it opened with for its whole life. Opened on a title you
    /// did not own, then played (which adds it), it still had no sources when you came back: Play
    /// searched the indexers and added ANOTHER copy to Real-Debrid, then started at 0:00. After
    /// "Download Whole Season" every episode still read "Not downloaded" and pressing one acquired
    /// it again. Only the same title is adopted — same kind, same TMDB id — and only when it is
    /// genuinely newer (the library item differs).
    public func adopt(_ owned: MediaItem) async {
        guard owned.kind == item.kind, let id = owned.tmdbID, id == item.tmdbID, owned != item
        else { return }
        let hadSeasons = !item.seasons.isEmpty
        item = owned
        removedSourceKeys = []                      // they described the old snapshot's files
        // A show opened with nothing owned sat on season 1; with episodes now owned, open on the
        // first season that has them — the same choice `init` makes for an owned show.
        if !hadSeasons, let first = owned.seasons.sortedBySeason().first?.number,
           !owned.seasons.contains(where: { $0.number == selectedSeason }) {
            await selectSeason(first)
        }
        await loadPreferredVersion()
        await reloadWatch()
        // The version rows' Hebrew marks describe files; the new files have their own.
        await loadStoredSubtitleEvidence()
        await loadSubtitleEvidence()
    }

    /// Called after a version was deleted from Real-Debrid: drop it from this screen, and retire a
    /// "play this one by default" preference that now points at nothing.
    public func forgetVersion(_ source: MediaSource) async {
        let key = WatchKey.source(source)
        removedSourceKeys.insert(key)
        if preferredSourceKey == key { await clearPreferredVersion() }
    }

    /// Whether this is the version Play will actually use — drives the Versions checkmark.
    public func isActive(_ source: MediaSource) -> Bool {
        bestSource.map { WatchKey.source($0) == WatchKey.source(source) } ?? false
    }

    public func loadPreferredVersion() async {
        preferredSourceKey = await versionPrefs?.preferred(forContentKey: item.id)
    }

    public func chooseVersion(_ source: MediaSource) async {
        let key = WatchKey.source(source)
        preferredSourceKey = key
        await versionPrefs?.choose(contentKey: item.id, sourceKey: key)
    }

    public func clearPreferredVersion() async {
        preferredSourceKey = nil
        await versionPrefs?.clear(contentKey: item.id)
    }

    /// Every season to show (TMDB's full count ∪ any owned seasons), sorted. Falls back to the owned
    /// seasons (or the selected one) until TMDB details resolve — so the picker lists ALL seasons,
    /// not just the downloaded ones.
    public var allSeasons: [Int] {
        var set = Set(item.seasons.map(\.number))
        if let n = numberOfSeasons, n > 0 { set.formUnion(1...n) }
        if set.isEmpty { set.insert(selectedSeason) }
        return set.sortedBySeason()
    }

    /// One row in a show's episode list: TMDB metadata plus the owned source when downloaded.
    public struct EpisodeRowInfo: Identifiable, Sendable {
        public let season: Int
        public let number: Int
        public let meta: TMDBEpisodeDetails?
        /// The owned `Episode` (play / watch-key / versions) when downloaded; nil = not yet.
        ///
        /// Holds the real episode rather than rebuilding one from a lone source. The rebuild
        /// dropped `alternates`, so every other copy you own was discarded on the way to the
        /// player and "Try another version" stayed unavailable even once the library kept them.
        public let ownedEpisode: Episode?

        public init(season: Int, number: Int, meta: TMDBEpisodeDetails?, ownedEpisode: Episode?) {
            self.season = season; self.number = number; self.meta = meta; self.ownedEpisode = ownedEpisode
        }

        public var id: String { "s\(season)e\(number)" }
        public var isDownloaded: Bool { ownedEpisode != nil }
        /// The copy that plays by default.
        public var ownedSource: MediaSource? { ownedEpisode?.source }
        /// Every owned copy, best-first — what a Versions picker lists.
        public var ownedVersions: [MediaSource] { ownedEpisode?.sources ?? [] }
        /// Whether offering a picker is worth it at all.
        public var hasAlternateVersions: Bool { !(ownedEpisode?.alternates.isEmpty ?? true) }
    }

    /// The full episode list for a season — every TMDB episode, merged with whatever is downloaded.
    /// Not-downloaded episodes still appear (`ownedSource == nil`) so the whole show is browsable.
    public func episodes(forSeason season: Int) -> [EpisodeRowInfo] {
        let owned = item.seasons.first { $0.number == season }?.episodes ?? []
        let ownedByNumber = Dictionary(owned.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        let metas = episodeMeta[season] ?? [:]
        let numbers = Set(metas.keys).union(owned.map(\.number)).sorted()
        return numbers.map { n in
            EpisodeRowInfo(season: season, number: n, meta: metas[n], ownedEpisode: ownedByNumber[n])
        }
    }

    /// Where a season's episode LIST has got to — distinct from whether any rows exist.
    public enum SeasonEpisodesState: Equatable, Sendable { case loading, loaded, failed }

    /// Whether an empty season is still coming, really empty, or failed.
    ///
    /// The tvOS page drew skeleton cards whenever a season had no rows, on the understanding that
    /// "no rows" meant "still loading". It also meant a fetch that failed, and a season TMDB lists
    /// with no episodes yet — both of which then showed grey placeholders forever, with nothing to
    /// press and no reason given.
    public func episodesState(forSeason n: Int) -> SeasonEpisodesState {
        if episodeMeta[n] != nil { return .loaded }
        if failedSeasons.contains(n) { return .failed }
        // No TMDB id: there is no list to fetch, so what the library owns is all there is.
        guard item.tmdbID != nil else { return .loaded }
        // The page's own details failed, so the season list was never asked for at all.
        if richState == .failed { return .failed }
        return .loading
    }

    /// Ask TMDB for the selected season's episodes again, after a failure.
    public func retrySeason() async {
        guard let tvID = item.tmdbID else { return }
        if richState == .failed {
            await load()                       // the details never arrived: start over
        } else {
            await loadSeason(selectedSeason, tvID: tvID)
        }
    }

    public func load() async {
        // Re-entrancy guard: one load per store (a retry after failure is still allowed).
        guard richState == .idle || richState == .failed else { return }
        richState = .loading
        await loadStoredSubtitleEvidence()
        // Watch state (local store) and TMDB details (network) are independent — overlap them so
        // neither delays the other. The async let must be awaited on every path below, or scope
        // exit would cancel the store reads mid-flight.
        async let watchLoad: Void = loadWatch()
        guard let tmdbID = item.tmdbID else {
            await watchLoad
            richState = .loaded
            return
        }
        do {
            switch item.kind {
            case .movie:
                let d = try await details.movieDetails(tmdbID: tmdbID)
                backdropPath = d.preferredBackdropPath ?? backdropPath
                logoPath = d.logoPath
                runtime = d.runtime
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                imdbID = d.imdbID
                originalLanguage = d.originalLanguage
                cast = d.cast
                director = d.director
                directors = d.directors
                similar = d.similar
                collectionRef = d.collection
            case .show:
                let d = try await details.tvDetails(tmdbID: tmdbID)
                backdropPath = d.preferredBackdropPath ?? backdropPath
                logoPath = d.logoPath
                genres = d.genres.map(\.name)
                overview = d.overview ?? overview
                imdbID = d.imdbID
                originalLanguage = d.originalLanguage
                numberOfSeasons = d.numberOfSeasons
                cast = d.cast
                creators = d.creators
                creatorRefs = d.creatorRefs
                similar = d.similar
                await loadSeason(selectedSeason, tvID: tmdbID)
            }
            await watchLoad
            if item.kind == .show { await openOnTheSeasonBeingWatched(tvID: tmdbID) }
            richState = .loaded
            // Overlapped, not sequential. Both add a row to the hero ABOVE the Play CTA, and run
            // one after the other they landed a network round-trip apart — so the page shifted
            // under the button focus was just placed on, twice. They are independent (OMDb
            // by imdbID; TMDB by collection), so they now settle together and sooner.
            async let ratingsLoad: Void = loadRatings()
            async let franchiseLoad: Void = loadFranchise()
            async let subtitleLoad: Void = loadSubtitleEvidence()
            _ = await (ratingsLoad, franchiseLoad, subtitleLoad)
        } catch {
            await watchLoad
            richState = .failed          // keep base info; no error wall
        }
    }

    /// Supplemental, non-blocking: enrich with the public scores once TMDB has given us the IMDb id.
    /// Failure leaves everything nil and the rest of the screen intact.
    private func loadRatings() async {
        // Concurrently, for the same reason the caller overlaps this with the franchise load: they
        // feed one row, and run in sequence they land a round-trip apart. Neither waits on the
        // other, so a slow Letterboxd page never holds the OMDb chips back.
        async let omdb: Void = loadOMDbRatings()
        async let letterboxd: Void = loadLetterboxdRating()
        _ = await (omdb, letterboxd)
    }

    /// What earlier visits learned, published before anything touches the network: a revisit's
    /// Play is the Hebrew copy from the first frame, however slow OpenSubtitles is today. Local
    /// reads only — a few milliseconds.
    private func loadStoredSubtitleEvidence() async {
        guard let provider = subtitleEvidence, item.kind == .movie, item.tmdbID != nil else { return }
        let key = WatchKey.content(forMovie: item)
        let stored = await provider.storedEvidence(for: item.sources, contentKey: key)
        let results = await provider.storedHebrewResults(contentKey: key)
        publishSubtitles(stored, results: results)
    }

    /// Hebrew subtitles for this film's versions: what each owned file carries, and what
    /// OpenSubtitles made for it. Movies only; a show's evidence is per episode, on its Versions
    /// screen. Lands in one piece, and on a revisit it usually matches what was already published,
    /// so nothing moves.
    private func loadSubtitleEvidence() async {
        guard let provider = subtitleEvidence, item.kind == .movie, item.tmdbID != nil else { return }
        let language = originalLanguage
        let query = SubtitleQuery.movie(item)
        let key = WatchKey.content(forMovie: item)
        async let search = provider.hebrewResults(contentKey: key, query: query, originalLanguage: language)
        let records = await provider.records(for: ownedSources)
        let results = await search
        publishSubtitles(.owned(item.sources, records: records, hebrewResults: results ?? [],
                                originalLanguage: language),
                         results: results)
    }

    /// Only what changed: every assignment re-renders everything observing it, and an equal
    /// re-publish would still re-sort the Versions list under the viewer's focus.
    private func publishSubtitles(_ evidence: SubtitleEvidenceSet, results: [SubtitleResult]?) {
        if evidence != subtitles { subtitles = evidence }
        if results != hebrewResults { hebrewResults = results }
    }

    private func loadOMDbRatings() async {
        // OMDb aggregate chips — only when a key is configured.
        if let provider = ratingsProvider, let imdb = imdbID {
            ratingsState = .loading
            do {
                ratings = try await provider.ratings(imdbID: imdb)
                ratingsState = .loaded
            } catch {
                ratingsState = .failed
            }
        }
    }

    /// Films only, and this guard is load-bearing for CORRECTNESS, not thrift.
    ///
    /// TMDB numbers films and shows in separate id spaces, and Letterboxd's `/tmdb/{id}/` endpoint
    /// only knows the film one. It does not reject a show's id — it silently resolves it to
    /// whatever film happens to hold that number. Measured: TMDB TV 1396 is Breaking Bad, and
    /// `letterboxd.com/tmdb/1396/` lands on `/film/mirror/`. Asking about a show would put a
    /// stranger's score on its page.
    private func loadLetterboxdRating() async {
        guard let provider = letterboxdProvider, item.kind == .movie, let tmdbID = item.tmdbID else {
            return
        }
        letterboxdState = .loading
        do {
            letterboxdRating = try await provider.rating(forTMDB: tmdbID)
            letterboxdState = .loaded
        } catch {
            letterboxdState = .failed
        }
    }

    /// Supplemental, non-blocking: resolve the franchise once TMDB has told us the film belongs to
    /// one. Costs a single request, and only for films that are part of a series. Any failure just
    /// leaves the badge and rail off the page.
    private func loadFranchise() async {
        guard item.kind == .movie, let ref = collectionRef, let tmdbID = item.tmdbID,
              let collection = try? await details.collection(id: ref.id) else { return }
        let ordered = FranchiseOrder.ordered(collection.parts, now: Date())
        // Two released films or it is not a series worth naming, and the viewer's own film has to
        // be one of them — otherwise "Film ? of 5" has nowhere to point.
        guard ordered.count >= 2,
              let position = FranchiseOrder.position(of: tmdbID, in: ordered) else { return }
        franchise = Franchise(name: collection.name, parts: ordered, position: position)
    }

    /// The viewer's history rollup (play count, last watched, "in your history since").
    /// Lazy — the views call it on appear, like `loadUserRating()`. Absent backend → stays nil.
    public func loadWatchSummary() async {
        guard let summaryProvider = watch as? WatchSummaryProviding else { return }
        watchSummary = await summaryProvider.watchSummary(forContentKey: item.id)
        historySince = await summaryProvider.historySince(forContentKey: item.id)
    }

    public func selectSeason(_ n: Int) async {
        selectedSeason = n
        await loadWatchForSeason(n)
        guard episodeMeta[n] == nil, let tvID = item.tmdbID else { return }
        await loadSeason(n, tvID: tvID)
    }

    public func watchState(forKey key: String) -> WatchState? { watchByKey[key] }

    /// Re-read watch state (the movie's key / the selected season's keys). Call when the player
    /// dismisses so Resume labels and checkmarks reflect the just-recorded progress instead of
    /// what was loaded when the screen opened.
    public func reloadWatch() async {
        // Drop the "already read these keys" claim first — this call exists precisely to pick up
        // state that changed since, so the de-duplication must not swallow it.
        watchKeysRead.removeAll()
        await loadWatch()
    }

    // MARK: - Personal rating

    /// The viewer's own 1–10 rating, or nil when unrated / unavailable. Distinct from `ratings`,
    /// which holds the aggregate public scores (IMDb / RT / Metacritic).
    public private(set) var userRating: Int?

    /// Ratings ride on the same object that supplies watch state (the local provider implements
    /// both), so nothing extra has to be injected. nil for fakes that don't.
    private var ratingSync: WatchRatingProviding? { watch as? WatchRatingProviding }

    /// The key a title's personal rating hangs off: the item id, which is already the enricher's
    /// `movie:tmdb:…` / `show:tmdb:…` identity — the same string both kinds of rating use.
    private var ratingKey: String { item.id }

    /// True when this title can carry a personal rating — a movie or a whole series. Ratings need a
    /// TMDB identity, so titles enrichment never matched can't be rated.
    public var canRate: Bool { ratingSync != nil && item.tmdbID != nil }

    public func loadUserRating() async {
        guard canRate, let ratingSync else { return }
        userRating = await ratingSync.rating(forContentKey: ratingKey)
    }

    /// Set (or clear, with nil) the viewer's rating. Optimistic: the UI updates immediately and the
    /// write is best-effort, matching how Mark Watched behaves.
    public func rate(_ value: Int?) async {
        guard canRate, let ratingSync else { return }
        userRating = value
        await ratingSync.setRating(value, forContentKey: ratingKey)
    }

    /// Mark a movie or episode watched/unwatched. `source` names the exact file when there is one;
    /// nil for a title you have not added, which is marked by content key alone.
    public func setWatched(_ watched: Bool, contentKey: String, source: MediaSource?) async {
        guard let watch else { return }
        await watch.setWatched(watched, contentKey: contentKey,
                               sourceKey: source.map(WatchKey.source) ?? "",
                               profileID: watchProfileID)
        await refreshWatch(contentKey)
    }

    /// Mark EVERY downloaded episode in a season watched/unwatched at once, then refresh that
    /// season's checkmarks. No-op for a season with no downloaded episodes.
    public func setSeasonWatched(_ watched: Bool, season n: Int) async {
        guard let watch, let season = item.seasons.first(where: { $0.number == n }) else { return }
        for ep in season.episodes {
            await watch.setWatched(watched, contentKey: WatchKey.content(forShow: item, episode: ep),
                                   source: ep.source, profileID: watchProfileID)
        }
        await loadWatchForSeason(n, force: true)
    }

    /// Whether the season has any downloaded episodes to mark — gates the "Mark Season" control.
    public func hasOwnedEpisodes(inSeason n: Int) -> Bool {
        !(item.seasons.first(where: { $0.number == n })?.episodes.isEmpty ?? true)
    }

    /// Every episode TMDB lists for the season is already in the library — gates "Download Whole
    /// Season", which on such a season could only add a duplicate torrent. Without TMDB's list there
    /// is no telling what is missing, so an unknown season is never "fully owned".
    public func isSeasonFullyOwned(_ n: Int) -> Bool {
        guard let listed = episodeMeta[n], !listed.isEmpty else { return false }
        let owned = Set(item.seasons.first(where: { $0.number == n })?.episodes.map(\.number) ?? [])
        return listed.keys.allSatisfy(owned.contains)
    }

    /// True when every downloaded episode of the season is finished — drives the toggle label.
    /// Reads whatever watch state is currently loaded (the selected season is loaded on entry).
    public func isSeasonWatched(_ n: Int) -> Bool {
        guard let season = item.seasons.first(where: { $0.number == n }), !season.episodes.isEmpty
        else { return false }
        return season.episodes.allSatisfy {
            watchByKey[WatchKey.content(forShow: item, episode: $0)]?.finished == true
        }
    }

    /// Build a playback request for a movie source or an episode.
    public func playRequest(source: MediaSource, episode: Episode?, label: String,
                     fromStart: Bool = false) -> PlaybackRequest {
        let key = episode.map { WatchKey.content(forShow: item, episode: $0) }
            ?? WatchKey.content(forMovie: item)
        let resume: Double? = fromStart ? nil : watchByKey[key]?.resumePosition
        // `resume` is only a hint — the player re-resolves the saved position from the store at
        // load time (see PlayerModel.resolveResume). `fromStart` carries the explicit intent.
        return PlaybackRequest(item: item, source: source, resumeAt: resume, label: label,
                               contentKey: key, episode: episode, fromStart: fromStart)
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

    /// What a show's Play starts, among the episodes you own. The episode touched most recently
    /// decides — the rule Continue Watching uses, so the page and Home agree: part-way through,
    /// resume it; finished, the one after it — nil when the series has a next one you don't own
    /// (`nextEpisodeTarget` fetches it). Nothing watched yet, or the series run out: the first
    /// episode not finished, regular seasons before the Specials. Uses whatever watch state is loaded.
    ///
    /// It used to take the FIRST part-way episode in series order, so an episode abandoned at 89%
    /// weeks ago outranked the one being watched tonight and Play dropped the viewer into its
    /// credits. And it only ever looked at what you own: finishing the last episode you had offered
    /// "Play S1·E1" although the next season was a press away.
    public func nextEpisode() -> Episode? {
        // Specials last: "what to play next" returning a show's unaired pilot is exactly the
        // bug that filing that pilot as S1E0 caused.
        let all = item.seasons.sortedBySeason()
            .flatMap { $0.episodes.sorted { $0.number < $1.number } }
        guard !all.isEmpty else { return nil }
        func owned(_ s: Int, _ n: Int) -> Episode? { all.first { $0.season == s && $0.number == n } }
        if let latest = latestTouchedEpisode() {
            if !latest.state.finished, let episode = owned(latest.season, latest.number) { return episode }
            if latest.state.finished, let next = successor(ofSeason: latest.season, number: latest.number) {
                return owned(next.season, next.number)   // nil → not yours yet: Play fetches it
            }
        }
        let regular = all.filter { $0.season != 0 }
        let pool = regular.isEmpty ? all : regular
        return pool.first { watchByKey[WatchKey.content(forShow: item, episode: $0)]?.finished != true }
            ?? pool.first
    }

    /// What Play should start for a show, addressed by NUMBERS so it works whether or not the
    /// episode is downloaded: the owned next episode when there is one; else the episode after the
    /// one finished last (or the one left part-way, if its file has gone); otherwise the first
    /// episode of the selected season that is not already finished.
    ///
    /// A show you have not added has no owned episode, and without this its page would have no Play
    /// button — which on tvOS also means `.defaultFocus` has nothing to focus and the remote dies.
    public func nextEpisodeTarget() -> (season: Int, number: Int)? {
        if let owned = nextEpisode() { return (owned.season, owned.number) }
        if let latest = latestTouchedEpisode() {
            if !latest.state.finished { return (latest.season, latest.number) }
            if let next = successor(ofSeason: latest.season, number: latest.number) { return next }
        }
        let rows = episodes(forSeason: selectedSeason)
        guard !rows.isEmpty else { return nil }
        let unwatched = rows.first {
            watchByKey[WatchKey.content(forShow: item, season: selectedSeason, number: $0.number)]?
                .finished != true
        }
        return (selectedSeason, (unwatched ?? rows[0]).number)
    }

    // MARK: - Private

    /// A show page opened on the first season you own, wherever you were — season 1 of a show you
    /// are halfway through season 3. It now opens where Play would take you. The season last
    /// touched is listed first, so "what comes after it" can see where that season ends.
    private func openOnTheSeasonBeingWatched(tvID: Int) async {
        if let latest = latestTouchedEpisode(), latest.season != 0, episodeMeta[latest.season] == nil {
            await loadSeason(latest.season, tvID: tvID)
        }
        guard let target = nextEpisodeTarget(), target.season != selectedSeason,
              allSeasons.contains(target.season) else { return }
        await selectSeason(target.season)
    }

    /// The episode of this show played or marked most recently, from the watch state loaded — owned
    /// or not, since an episode can be watched and its file later removed.
    private func latestTouchedEpisode() -> (season: Int, number: Int, state: WatchState)? {
        let prefix = item.id + ":"
        var latest: (season: Int, number: Int, state: WatchState)?
        for (key, state) in watchByKey where key.hasPrefix(prefix) {
            guard state.finished || state.positionSeconds > 0,
                  let (season, number) = Self.episodeNumbers(String(key.dropFirst(prefix.count)))
            else { continue }
            // A tie — a whole season marked at once — goes to the episode latest in the series.
            if latest.map({ (state.updatedAt, season, number) > ($0.state.updatedAt, $0.season, $0.number) })
                ?? true {
                latest = (season, number, state)
            }
        }
        return latest
    }

    /// "s2e5" → (2, 5).
    static func episodeNumbers(_ id: String) -> (Int, Int)? {
        let lower = id.lowercased()
        guard lower.hasPrefix("s"), let e = lower.firstIndex(of: "e"),
              let season = Int(lower[lower.index(after: lower.startIndex)..<e]),
              let number = Int(lower[lower.index(after: e)...]) else { return nil }
        return (season, number)
    }

    /// The episode after (season, number), from what you own and what TMDB lists. Never from a
    /// regular season into the Specials, and nil once the series has nothing later.
    private func successor(ofSeason s: Int, number n: Int) -> (season: Int, number: Int)? {
        guard s != 0 else { return nil }
        let ownedHere = Set(item.seasons.first { $0.number == s }?.episodes.map(\.number) ?? [])
        if ownedHere.contains(n + 1) { return (s, n + 1) }
        if let listed = episodeMeta[s] {
            if listed[n + 1] != nil { return (s, n + 1) }
        } else if ownedHere.contains(where: { $0 > n }) {
            return (s, n + 1)          // a gap in what you own, in a season TMDB has not listed yet
        }
        let nextSeasonOwned = item.seasons.contains { $0.number == s + 1 && !$0.episodes.isEmpty }
        if nextSeasonOwned || (numberOfSeasons.map { s + 1 <= $0 } ?? false) { return (s + 1, 1) }
        return nil
    }

    private func loadSeason(_ n: Int, tvID: Int) async {
        failedSeasons.remove(n)          // a retry is loading again until it says otherwise
        do {
            let eps = try await details.seasonEpisodes(tvID: tvID, season: n)
            episodeMeta[n] = Dictionary(eps.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // leave episodeMeta[n] nil → owned rows degrade to "Episode N"; selecting the season
            // again retries. Recorded, so an empty season says it failed instead of loading forever.
            failedSeasons.insert(n)
        }
        // TMDB's episode list can be bigger than what you own — for a show you have not added it is
        // the ONLY list — so keys that did not exist when watch state was first read do now.
        // `loadWatchForSeason` skips itself when the key set is unchanged.
        await loadWatchForSeason(n)
    }

    private func loadWatch() async {
        switch item.kind {
        case .movie: await refreshWatch(WatchKey.content(forMovie: item))
        case .show:
            // Every OWNED episode of every season, in one read, BEFORE the selected season's.
            // `nextEpisode()` scans all seasons and treats an episode with no loaded state as
            // unwatched — so reading only the selected season made every season the viewer had not
            // opened on this visit look untouched, and Play offered the first episode of the
            // earliest unvisited season instead of the one actually in progress.
            await loadWatchForOwnedEpisodes()
            await loadWatchForSeason(selectedSeason)
        }
    }

    /// One batched read covering every episode the show OWNS, across all seasons. Bounded by the
    /// download count, not by TMDB's catalogue, and it is what `nextEpisode()` reasons over.
    private func loadWatchForOwnedEpisodes() async {
        guard let watch else { return }
        let keys = item.seasons.flatMap { season in
            season.episodes.map { WatchKey.content(forShow: item, episode: $0) }
        }
        guard !keys.isEmpty else { return }
        // Claim the keys BEFORE the read, with no await between deciding to read them and saying
        // so — the same discipline `loadWatchForSeason` documents below, and for the same reason.
        //
        // Claiming them AFTERWARDS left the entire duration of the read unclaimed. `load()` runs
        // this concurrently with the TMDB fetch, so whenever the details came back first — which
        // is whenever the store read is the slower of the two, i.e. whenever the machine is busy —
        // `loadSeason`'s own watch read found nothing claimed and issued a SECOND batched read for
        // the very episodes already in flight. Two identical store reads per show page, and the
        // test that pins this to one read failed about one run in three.
        let claimed = keys.filter { !watchKeysRead.contains($0) }
        watchKeysRead.formUnion(claimed)
        guard let states = try? await watch.progress(forContentKeys: keys,
                                                     profileID: watchProfileID) else {
            watchKeysRead.subtract(claimed)   // a failed read must not block the retry
            return
        }
        for key in keys { watchByKey[key] = states[key] }
    }

    /// Read watch state for every episode the season LISTS — TMDB's episodes merged with whatever
    /// is downloaded, not just the downloaded ones. A show you have not added owns no episodes, and
    /// it still needs its checkmarks.
    /// `force` re-reads even when the key set is unchanged — for callers that just CHANGED the
    /// state and need the new values, not the de-duplication.
    private func loadWatchForSeason(_ n: Int, force: Bool = false) async {
        guard let watch else { return }
        let keys = episodes(forSeason: n).map {
            WatchKey.content(forShow: item, season: n, number: $0.number)
        }
        // Ask only about keys nothing has read yet.
        //
        // `load()` starts the watch read concurrently with the TMDB fetch, and `loadSeason` reads
        // again once the episode list lands — because for a show you do not own, that list is the
        // only thing that says which keys exist. Claiming the keys here, with no await between the
        // check and the write, makes the pair deterministic: whichever runs first reads them, and
        // the other is left with only what is genuinely new.
        //
        // Tracked as a flat key set rather than per-season sets. A per-season set had to be
        // compared whole, so whether it matched depended on how much of the TMDB episode list had
        // landed when it was written — the same screen would issue one read or two depending on
        // which of two concurrent loads won.
        let wanted = force ? keys : keys.filter { !watchKeysRead.contains($0) }
        guard !wanted.isEmpty else { return }
        watchKeysRead.formUnion(wanted)
        // One batched read — not a store round-trip per episode.
        guard let states = try? await watch.progress(forContentKeys: wanted, profileID: watchProfileID)
        else {
            watchKeysRead.subtract(wanted)   // a failed read must not block the retry
            return
        }
        for key in wanted { watchByKey[key] = states[key] }
    }

    /// Every episode key a watch read has already covered. Also what `reloadWatch()` clears, so
    /// re-reading after playback is never mistaken for a duplicate.
    private var watchKeysRead: Set<String> = []

    /// The id the player saves progress under is `activeProfileID ?? ""` (see `AppSession.makePlayer`).
    /// Read/write under the SAME fallback so a nil active profile doesn't silently skip the resume
    /// read — which made "Resume" do nothing because `watchByKey` never got the saved position.
    private var watchProfileID: String { profileID ?? "" }

    private func refreshWatch(_ key: String) async {
        guard let watch else { return }
        watchByKey[key] = try? await watch.progress(forContentKey: key, profileID: watchProfileID)
    }

    /// Load whether the active profile has claimed this title (for the Add-to-My-List button).
    public func loadMyList(contentKey: String) async {
        guard let myList, let profileID else { inMyList = false; return }
        inMyList = (try? await myList.isClaimed(profileID: profileID, contentKey: contentKey)) ?? false
    }

    /// Add or remove this title from the active profile's My List.
    public func toggleMyList(contentKey: String) async {
        guard let myList, let profileID else { return }
        if inMyList {
            try? await myList.unclaim(profileID: profileID, contentKey: contentKey)
            inMyList = false
        } else {
            try? await myList.claim(profileID: profileID, contentKey: contentKey)
            inMyList = true
        }
    }
}
