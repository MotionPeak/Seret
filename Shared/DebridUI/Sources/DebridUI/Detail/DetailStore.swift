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

    public let item: MediaItem
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
                letterboxd: LetterboxdRatingProviding? = nil) {
        self.item = item
        self.details = details
        self.watch = watch
        self.profileID = profileID
        self.myList = myList
        self.ratingsProvider = ratings
        self.letterboxdProvider = letterboxd
        self.versionPrefs = versionPrefs
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        // Viewing order, so a show that owns only its Specials plus season 1 does not open on
        // the extras — `item.seasons` is built in that order, but this must not depend on it.
        self.selectedSeason = item.seasons.sortedBySeason().first?.number ?? 1
    }

    // Movies: ranked sources.
    public var versions: [MediaSource] { ownedSources.bestFirst() }

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
    public var bestSource: MediaSource? { ownedSources.preferred(preferredSourceKey) }

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

    public func load() async {
        // Re-entrancy guard: one load per store (a retry after failure is still allowed).
        guard richState == .idle || richState == .failed else { return }
        richState = .loading
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
            richState = .loaded
            // Overlapped, not sequential. Both add a row to the hero ABOVE the Play CTA, and run
            // one after the other they landed a network round-trip apart — so the page shifted
            // under the button focus was just placed on, twice. They are independent (OMDb
            // by imdbID; TMDB by collection), so they now settle together and sooner.
            async let ratingsLoad: Void = loadRatings()
            async let franchiseLoad: Void = loadFranchise()
            _ = await (ratingsLoad, franchiseLoad)
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

    /// Letterboxd indexes films only, and can be reached by TMDB id alone. A show, or a title with
    /// no TMDB id, is not asked about at all — the answer is known, and asking would spend a
    /// request on every title-page open to be told it.
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

    /// Best-effort "what to play next" for a show's hero: first in-progress episode (series
    /// order), else the first not-known-finished episode, else the very first. Uses whatever
    /// watch state is currently loaded.
    public func nextEpisode() -> Episode? {
        // Specials last: "what to play next" returning a show's unaired pilot is exactly the
        // bug that filing that pilot as S1E0 caused.
        let all = item.seasons.sortedBySeason()
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

    /// What Play should start for a show, addressed by NUMBERS so it works whether or not the
    /// episode is downloaded: the owned next episode when there is one, otherwise the first episode
    /// of the selected season that is not already finished.
    ///
    /// A show you have not added has no owned episode, and without this its page would have no Play
    /// button — which on tvOS also means `.defaultFocus` has nothing to focus and the remote dies.
    public func nextEpisodeTarget() -> (season: Int, number: Int)? {
        if let owned = nextEpisode() { return (owned.season, owned.number) }
        let rows = episodes(forSeason: selectedSeason)
        guard !rows.isEmpty else { return nil }
        let unwatched = rows.first {
            watchByKey[WatchKey.content(forShow: item, season: selectedSeason, number: $0.number)]?
                .finished != true
        }
        return (selectedSeason, (unwatched ?? rows[0]).number)
    }

    // MARK: - Private

    private func loadSeason(_ n: Int, tvID: Int) async {
        do {
            let eps = try await details.seasonEpisodes(tvID: tvID, season: n)
            episodeMeta[n] = Dictionary(eps.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            // leave episodeMeta[n] nil → rows degrade to "Episode N"
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
