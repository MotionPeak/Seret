import DebridCore
import Foundation
import Observation
import SwiftData

/// Owns the one shared `RealDebridSession` and the app's coarse auth state. It is the
/// `AccessTokenProviding` source that 7b's library + 7c's playback will consume.
@MainActor
@Observable
public final class AppSession {
    public enum State: Equatable { case unknown, signedIn, signedOut }

    public private(set) var state: State = .unknown

    /// The sign-in model for the current signed-out episode (nil while signed in or
    /// unresolved). Built when *entering* `.signedOut` so the view never creates it
    /// during `body` evaluation.
    public private(set) var signInModel: SignInModel?

    /// The library store for the current signed-in episode (nil while signed out).
    public private(set) var libraryStore: LibraryStore?

    /// Title-search store for the Stage 2 Search tab (nil while signed out).
    public private(set) var searchStore: SearchStore?

    /// Browse rows for the Movies / TV tabs (nil while signed out).
    public private(set) var moviesBrowse: DiscoverStore?
    public private(set) var showsBrowse: DiscoverStore?

    /// Trailer-key resolver for the Add / Detail screens (nil while signed out).
    public private(set) var trailers: TrailerProviding?

    /// On-demand TMDB detail provider for the Detail screen (nil while signed out).
    public private(set) var detailsProvider: MediaDetailsProviding?

    /// Shared watch-progress store (nil while signed out, or if the container fails to build).
    /// 7c's player + a later Continue-Watching feed reuse this same instance.
    public private(set) var watchStore: WatchProgressProviding?

    /// Home feed (Continue Watching + Recently Added), composed from the library + watch store.
    public private(set) var home: HomeStore?

    /// On-demand OpenSubtitles provider (nil while signed out or if no key+account configured).
    public private(set) var subtitlesProvider: SubtitleProvider?

    /// Global subtitle appearance (size · font · color), persisted and applied to every playback.
    /// Survives sign-out (it's a device preference, not session state).
    public let subtitleSettings = SubtitleSettingsModel()

    /// Trailer auto-play preference, persisted; survives sign-out (a device setting).
    public let trailerSettings = TrailerSettingsModel()
    private var watchProgressStore: WatchProgressStore?   // concrete ref for PlaybackCoordinator
    private var torrents: TorrentsClient?

    /// Stage 2 Add-flow seams, composed at sign-in and consumed by the per-title `AddStore`
    /// the `makeAddStore(...)` factory vends (nil while signed out).
    private var streamSource: StreamSource?
    private var addService: AddProviding?

    /// Resolves a YouTube key → direct stream URL (YouTubeKit), composed at sign-in.
    private var trailerResolver: TrailerStreamResolving?

    /// Request-Download (uncached titles) seams, composed at sign-in (nil while signed out).
    private var downloadService: DownloadRequesting?
    private var downloadsStore: DownloadsStore?
    private var downloadMonitor: DownloadMonitor?

    /// Request-Download view-model: live per-title progress + library "downloading" badge
    /// (nil while signed out, or if the SwiftData container fails to build).
    public private(set) var downloadStore: DownloadStore?

    /// Posts a local notification when a requested download finishes. Survives sign-out (the
    /// permission grant is a device setting, not session state).
    public let downloadNotifier = DownloadNotifier()

    public let realDebrid: RealDebridSession

    public init(realDebrid: RealDebridSession) {
        self.realDebrid = realDebrid
    }

    /// Resolve launch state from persisted credentials. `validAccessToken()` throws
    /// `.notSignedIn` ONLY when there are no stored credentials, which lets us treat
    /// offline-with-credentials as optimistically signed in (spec §143) while a server
    /// rejection of the refresh token routes back to sign-in (spec §165).
    public func resolve() async {
        do {
            _ = try await realDebrid.validAccessToken()
            enterSignedIn()
        } catch RealDebridSessionError.notSignedIn {
            enterSignedOut()
        } catch HTTPError.status(_, _) {
            // RD actively rejected the stored/refresh token → must re-authenticate.
            enterSignedOut()
        } catch {
            // Transport/offline but credentials exist: stay signed in; later calls retry.
            // (A genuine decoding bug would also land here as optimistic-signedIn; the
            // first real library call in 7b surfaces it — acceptable for this slice.)
            enterSignedIn()   // transport/offline with stored creds: optimistic
        }
    }

    func markSignedIn() {
        enterSignedIn()
        signInModel = nil
    }

    public func signOut() async {
        try? await realDebrid.signOut()
        enterSignedOut()
    }

    /// Enter `.signedOut` with a fresh sign-in model for the new episode.
    private func enterSignedOut() {
        guard state != .signedOut else { return }
        signInModel = SignInModel(
            flow: LiveAuthFlow(auth: RealDebridAuthClient(), session: realDebrid),
            onSignedIn: { [weak self] in self?.markSignedIn() })
        libraryStore = nil
        searchStore = nil
        moviesBrowse = nil
        showsBrowse = nil
        trailers = nil
        detailsProvider = nil
        watchStore = nil
        home = nil
        watchProgressStore = nil
        torrents = nil
        trailerResolver = nil
        streamSource = nil
        addService = nil
        downloadService = nil
        downloadsStore = nil
        downloadMonitor = nil
        downloadStore = nil
        subtitlesProvider = nil
        state = .signedOut
    }

    /// Enter `.signedIn`, composing the DebridCore library pipeline once. Thin glue: the app
    /// assembles brain objects and reads a config value; no RD/TMDB logic lives here.
    private func enterSignedIn() {
        guard state != .signedIn else { return }
        let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        let torrents = TorrentsClient(tokens: realDebrid)
        self.torrents = torrents
        let service = LibraryService(
            torrents: torrents,
            builder: LibraryBuilder(),
            enricher: MetadataEnricher(tmdb: tmdb),
            store: LibrarySnapshotStore(directory: Self.cachesDirectory))
        // Build the watch store first so LibraryStore can purge a removed item's progress.
        let concreteStore = (try? ModelContainer(for: WatchProgress.self))
            .map { WatchProgressStore(modelContainer: $0) }
        watchProgressStore = concreteStore
        watchStore = concreteStore.map { $0 as WatchProgressProviding }
        libraryStore = LibraryStore(library: service, watch: watchStore)
        searchStore = SearchStore(search: TMDBSearchService(client: tmdb))
        let discover = TMDBDiscoverService(client: tmdb)
        moviesBrowse = DiscoverStore(kind: .movie, discover: discover)
        showsBrowse = DiscoverStore(kind: .show, discover: discover)
        trailers = TMDBTrailerService(client: tmdb)
        trailerResolver = YouTubeKitStreamResolver()
        // Comet = accurate instant-cache flags; Torrentio = broad index incl. brand-new CAMs.
        streamSource = AggregateStreamSource([CometStreamSource(tokens: realDebrid),
                                              TorrentioStreamSource()])
        addService = RealDebridAddService(torrents: torrents)
        let dlService = RealDebridDownloadService(torrents: torrents)
        downloadService = dlService
        if let container = try? ModelContainer(for: DownloadRequest.self) {
            let dStore = DownloadsStore(modelContainer: container)
            let dMonitor = DownloadMonitor(info: torrents, store: dStore)
            downloadsStore = dStore
            downloadMonitor = dMonitor
            // A finished download flips into the normal library — refresh so it appears + Play lights
            // up — and fires a "ready" notification (the title is still in DownloadStore's meta here).
            let store = DownloadStore(service: dlService, records: dStore, poller: dMonitor,
                                      deleter: torrents,
                                      onReady: { [weak self] tmdbID in
                                          guard let self else { return }
                                          let name = self.downloadStore?.title(forTMDB: tmdbID) ?? "Your download"
                                          self.libraryStore?.retry()
                                          self.downloadNotifier.notifyReady(title: name)
                                      })
            downloadStore = store
            Task { await store.loadActive() }
            Task { await downloadNotifier.requestAuthorization() }
        }
        detailsProvider = TMDBDetailsService(client: tmdb)
        home = watchStore.map { HomeStore(watch: $0) }
        // Recompute the Home rails the moment a removal changes the library, so a deleted title
        // doesn't linger in Continue Watching / Recently Added until the Home tab is revisited.
        if let home {
            libraryStore?.onContentChanged = { [weak libraryStore] in
                guard let libraryStore else { return }
                await home.rebuild(movies: libraryStore.movies, shows: libraryStore.shows)
            }
        }
        let osKey = Secrets.openSubtitlesAPIKey
        if !osKey.isEmpty,
           let account = KeychainSecretStore(service: "com.solomons.seret.opensubtitles").readAccount() {
            subtitlesProvider = OpenSubtitlesProvider(apiKey: osKey, credentials: account.credentials)
        } else {
            subtitlesProvider = nil
        }
        state = .signedIn
    }

    /// Build a fully-wired player for a playback request, or nil if not signed in. The platform
    /// engine + thumbnail source are injected by the app target (VLCKit is per-platform), so this
    /// shared factory owns only the brain wiring (unrestrict / progress / subtitles).
    public func makePlayer(for request: PlaybackRequest,
                           engine: VideoPlayerEngine) -> PlayerModel? {
        guard let torrents, let store = watchProgressStore else { return nil }
        let coordinator = PlaybackCoordinator(store: store)
        return PlayerModel(
            request: request,
            engine: engine,
            unrestrict: { link in
                let unrestricted = try await torrents.unrestrict(link: link)
                guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
                return url
            },
            // PlayerModel supplies the live contentKey/sourceKey so a next-episode advance records
            // against the new episode rather than the one playback started on.
            recordProgress: { contentKey, sourceKey, position, duration in
                await coordinator.record(contentKey: contentKey, sourceKey: sourceKey,
                                         position: position, duration: duration)
            },
            subtitles: subtitlesProvider)
    }

    /// Vend a `TrailerModel` for a title (nil while signed out). Chains the TMDB key provider with
    /// the YouTubeKit resolver and reads the persisted autoplay setting.
    public func makeTrailerModel() -> TrailerModel? {
        guard let trailers, let trailerResolver else { return nil }
        return TrailerModel(trailers: trailers, resolver: trailerResolver,
                            autoplayEnabled: { [trailerSettings] in trailerSettings.autoplayTrailers })
    }

    /// Vend a per-title `AddStore` for the chosen TMDB title, or nil if not signed in.
    /// `AddStore` is per-title (it carries the imdbID/kind/originalLanguage), so it is built
    /// on demand rather than held on the session like `searchStore`.
    public func makeAddStore(imdbID: String, kind: StreamQuery.Kind,
                             originalLanguage: String?) -> AddStore? {
        guard let streamSource, let addService else { return nil }
        return AddStore(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage,
                        streamSource: streamSource, add: addService)
    }

    /// Vend a whole-season download engine (nil while signed out / Stage 2 unavailable). Used by the
    /// library show page to grab the best full-season pack for `season`, caching every episode at once.
    public func makeSeasonDownload(imdbID: String, season: Int, originalLanguage: String?) -> AddStore? {
        guard let streamSource, let addService else { return nil }
        return AddStore(imdbID: imdbID, kind: .series(season: season, episode: 1),
                        originalLanguage: originalLanguage, streamSource: streamSource,
                        add: addService, seasonPack: season)
    }

    /// Vend the Add-flow orchestrator for a picked search hit (nil while signed out). It
    /// resolves the title's TMDB details, then drives the per-target `AddStore` itself.
    public func makeAddFlow(for hit: SearchHit) -> AddFlowStore? {
        guard let detailsProvider, let streamSource, let addService else { return nil }
        return AddFlowStore(hit: hit, details: detailsProvider,
                            streamSource: streamSource, add: addService)
    }

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
