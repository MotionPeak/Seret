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

    /// On-demand OMDb ratings provider for the Detail screen (nil while signed out or no key).
    public private(set) var ratingsProvider: RatingsProviding?

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

    /// Preferred audio/subtitle language, persisted and auto-applied to every playback; survives
    /// sign-out (a device preference). Recorded by `PlayerModel` when the user picks a track.
    public let trackPreferences = TrackPreferences()
    private var watchProgressStore: WatchProgressStore?   // concrete ref for PlaybackCoordinator
    /// Profile roster store (CRUD) — used by the Who's-Watching / profile-manager UI (later slice).
    public private(set) var profileStore: ProfileStore?
    /// Per-profile "My List" store — claimed-title membership (later slice wires claim on add/play).
    public private(set) var myListStore: MyListStore?
    /// Device-local active-profile selection + roster (drives the Who's-Watching gate).
    public private(set) var activeProfiles: ActiveProfileStore?
    /// The profile this device is watching as (nil until resolved / while the gate is showing).
    public var activeProfileID: String? { activeProfiles?.activeProfileID }
    /// True when the Who's-Watching gate should show (more than one profile, none chosen here).
    public var needsProfileSelection: Bool { activeProfiles?.needsSelection ?? false }
    private var torrents: TorrentsClient?
    /// Single, app-lifetime observer that rebuilds Home when CloudKit imports remote changes.
    private var remoteChangeObserver: NSObjectProtocol?

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
        ratingsProvider = nil
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

    /// The shared CloudKit container both Seret apps sync through (one private DB per Apple ID).
    private static let cloudKitContainerID = "iCloud.com.solomons.seret"

    /// The watch-progress + profile + My-List stores, built from ONE CloudKit-backed container so
    /// cascade-delete + owner migration work across them and they share a single private DB. Falls
    /// back to local-only if iCloud/CloudKit is unavailable so the app still works offline.
    private struct ProfileStores {
        let watch: WatchProgressStore
        let profiles: ProfileStore
        let myList: MyListStore
        let mode: String
    }

    /// Which backing store profiles use ("cloud", "local", "local-reset", or "none").
    public private(set) var profileStoreMode: String = "none"
    /// True when profiles are backed by CloudKit (syncing across this Apple ID's devices); false
    /// means a local-only store on this device (no iCloud account / CloudKit unavailable).
    public var profilesSyncedViaICloud: Bool { profileStoreMode == "cloud" }

    private static func makeProfileStores() -> ProfileStores? {
        let schema = Schema([WatchProgress.self, Profile.self, MyListEntry.self])
        // Only ask for CloudKit when an iCloud account is actually signed in (a CloudKit store fails
        // silently on a sim / no-account device). Otherwise local-only — sync engages on real
        // iCloud devices.
        let useCloudKit = FileManager.default.ubiquityIdentityToken != nil
        let mode = useCloudKit ? "cloud" : "local"

        if let container = makeContainer(schema: schema, cloudKit: useCloudKit), storeHealthy(container) {
            return wrap(container, mode: mode)
        }
        // The dedicated store is incompatible (e.g. left over from an earlier schema). Wipe it and
        // rebuild fresh (local) so profiles always work. Watch progress is re-derivable.
        destroyProfileStore()
        guard let container = makeContainer(schema: schema, cloudKit: false) else { return nil }
        return wrap(container, mode: mode + "-reset")
    }

    /// A DEDICATED store file under Application Support. EVERY SwiftData container gets its own file
    /// (profiles, downloads) so two containers can NEVER share one store — sharing `default.store`
    /// with different schemas (and CloudKit) clobbered tables and double-registered CloudKit sync,
    /// which broke profiles entirely ("no such table: ZPROFILE", "another instance … syncing").
    static func dedicatedStoreURL(_ name: String) -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(name)
    }

    private static var profileStoreURL: URL? { dedicatedStoreURL("SeretProfiles.store") }

    /// Delete the orphaned legacy `default.store` (and sidecars) from every location it may have
    /// been created in. Older builds put the profile + downloads containers there together — that
    /// file carries broken tables + CloudKit metadata that crash the new dedicated stores. Nothing
    /// uses `default.store` anymore, so wiping it is safe and stops the conflict for good.
    static func purgeLegacyDefaultStore() {
        let dirs: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .cachesDirectory,
                                                       .documentDirectory]
        for dir in dirs {
            guard let base = try? FileManager.default.url(for: dir, in: .userDomainMask,
                                                          appropriateFor: nil, create: false) else { continue }
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: base.appendingPathComponent("default.store" + suffix))
            }
        }
    }

    private static func makeContainer(schema: Schema, cloudKit: Bool) -> ModelContainer? {
        guard let url = profileStoreURL else {
            // No dedicated URL available — last-resort in-memory store so the app still runs.
            return try? ModelContainer(for: schema,
                                       configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        let local = ModelConfiguration(schema: schema, url: url)
        let config = cloudKit
            ? ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private(cloudKitContainerID))
            : local
        return (try? ModelContainer(for: schema, configurations: config))
            ?? (try? ModelContainer(for: schema, configurations: local))
    }

    private static func wrap(_ container: ModelContainer, mode: String) -> ProfileStores {
        ProfileStores(watch: WatchProgressStore(modelContainer: container),
                      profiles: ProfileStore(modelContainer: container),
                      myList: MyListStore(modelContainer: container), mode: mode)
    }

    /// A `Profile` fetch on a stale store throws ("no such table: ZPROFILE"); a healthy store
    /// returns (even if empty). Probes synchronously via a throwaway context.
    private static func storeHealthy(_ container: ModelContainer) -> Bool {
        let ctx = ModelContext(container)
        do { _ = try ctx.fetch(FetchDescriptor<Profile>()); return true }
        catch { return false }
    }

    /// Delete the dedicated profile store (and its WAL/SHM sidecars) so a fresh, correctly-schema'd
    /// store is recreated. Used only when the existing store is incompatible.
    private static func destroyProfileStore() {
        guard let url = profileStoreURL else { return }
        let dir = url.deletingLastPathComponent(), name = url.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name + suffix))
        }
    }

    /// Re-run the profile load (owner migration + roster) and re-scope Home. Exposed so the
    /// Who's-Watching screen can offer a manual "Reload" while we diagnose.
    public func reloadProfiles() async {
        await activeProfiles?.loadAndResolve()
        home?.activeProfileID = activeProfileID
        await rebuildHome()
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
            store: LibrarySnapshotStore(directory: Self.dataDirectory))
        // Remove the orphaned legacy `default.store` (old builds shared it across containers + had
        // CloudKit metadata) BEFORE opening any store, so it can't double-register CloudKit sync.
        Self.purgeLegacyDefaultStore()
        // Build the watch + profile + My-List stores from one dedicated container.
        let stores = Self.makeProfileStores()
        watchProgressStore = stores?.watch
        watchStore = stores?.watch as WatchProgressProviding?
        profileStore = stores?.profiles
        myListStore = stores?.myList
        profileStoreMode = stores?.mode ?? "none"
        libraryStore = LibraryStore(library: service, watch: watchStore)
        searchStore = SearchStore(search: TMDBSearchService(client: tmdb))
        let discover = TMDBDiscoverService(client: tmdb)
        let seedService = RecommendationSeedService(
            watch: watchStore ?? NoWatch(), library: libraryStore,
            profileID: { [weak self] in self?.activeProfileID })
        moviesBrowse = DiscoverStore(kind: .movie, discover: discover, seeds: seedService)
        showsBrowse = DiscoverStore(kind: .show, discover: discover, seeds: seedService)
        trailers = TMDBTrailerService(client: tmdb)
        trailerResolver = YouTubeKitStreamResolver()
        // Comet = accurate instant-cache flags; Torrentio = broad index incl. brand-new CAMs.
        streamSource = AggregateStreamSource([CometStreamSource(tokens: realDebrid),
                                              TorrentioStreamSource()])
        addService = RealDebridAddService(torrents: torrents)
        let dlService = RealDebridDownloadService(torrents: torrents)
        downloadService = dlService
        // Downloads get their OWN dedicated store file — never `default.store`, so they can't
        // collide with the profile/watch store (the bug that kept dropping the profile tables).
        let downloadsContainer: ModelContainer? = {
            if let url = Self.dedicatedStoreURL("SeretDownloads.store"),
               let c = try? ModelContainer(for: DownloadRequest.self,
                                           configurations: ModelConfiguration(schema: Schema([DownloadRequest.self]), url: url)) {
                return c
            }
            return try? ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(schema: Schema([DownloadRequest.self]),
                                                                          isStoredInMemoryOnly: true))
        }()
        if let container = downloadsContainer {
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
        let omdbKey = Secrets.omdbAPIKey
        ratingsProvider = omdbKey.isEmpty ? nil
            : OMDbRatingsService(client: OMDbClient(apiKey: omdbKey),
                                 cache: OMDbRatingsCache(directory: Self.dataDirectory))
        home = watchStore.map { HomeStore(watch: $0) }
        // Recompute the Home rails the moment a removal changes the library, so a deleted title
        // doesn't linger in Continue Watching / Recently Added until the Home tab is revisited.
        if let home {
            libraryStore?.onContentChanged = { [weak libraryStore] in
                guard let libraryStore else { return }
                await home.rebuild(movies: libraryStore.movies, shows: libraryStore.shows)
            }
        }
        observeRemoteChanges()
        let osKey = Secrets.openSubtitlesAPIKey
        if !osKey.isEmpty,
           let account = KeychainSecretStore(service: "com.solomons.seret.opensubtitles").readAccount() {
            subtitlesProvider = OpenSubtitlesProvider(apiKey: osKey, credentials: account.credentials)
        } else {
            subtitlesProvider = nil
        }
        // Profiles: ensure an owner profile exists (migrating Phase-1 progress), resolve this
        // device's selection (solo → auto-select; multiple → Who's-Watching gate), and scope Home.
        if let profileStore {
            let profiles = ActiveProfileStore(provider: profileStore)
            activeProfiles = profiles
            Task { @MainActor in
                await profiles.loadAndResolve()
                self.home?.activeProfileID = profiles.activeProfileID
                await self.rebuildHome()
            }
        }
        state = .signedIn
    }

    /// Pick a profile (Who's-Watching tap): persist the device selection, re-scope Home, rebuild.
    public func selectProfile(_ id: String) {
        activeProfiles?.select(id)
        home?.activeProfileID = activeProfileID
        Task { await rebuildHome() }
    }

    /// Switch user — clears the device selection so the Who's-Watching gate reappears.
    public func switchProfile() {
        activeProfiles?.switchProfile()
        home?.activeProfileID = nil
    }

    /// Create a profile (then it can be picked on the Who's-Watching screen).
    public func createProfile(name: String, colorTag: String, avatar: String) async {
        await activeProfiles?.create(name: name, colorTag: colorTag, avatar: avatar)
    }

    /// Edit an existing profile's name, color, and avatar.
    public func updateProfile(id: String, name: String, colorTag: String, avatar: String) async {
        await activeProfiles?.update(id: id, name: name, colorTag: colorTag, avatar: avatar)
    }

    /// Delete a profile (cascades its progress + My List via the store).
    public func deleteProfile(_ id: String) async {
        await activeProfiles?.delete(id: id)
        home?.activeProfileID = activeProfileID
        await rebuildHome()
    }

    /// Rebuild the Home rails from the current library + (possibly just-synced) watch progress.
    private func rebuildHome() async {
        guard let library = libraryStore, let home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
    }

    /// Public refresh so a screen can update Continue Watching after playback writes progress
    /// (the Home tab is kept alive, so its `.task` doesn't re-run when you return to it).
    public func refreshHome() async { await rebuildHome() }

    /// Install once: when the persistent store imports CloudKit changes, refresh Home so a title
    /// watched on another device shows up in Continue Watching without relaunch. `[weak self]` +
    /// app-lifetime single instance → no retain cycle, no teardown needed.
    private func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // A CloudKit import can bring in a profile created on another device — refresh the
                // roster (without changing this device's selection) so it appears, then Home.
                await self?.activeProfiles?.reloadRoster()
                await self?.rebuildHome()
            }
        }
    }

    /// Build a fully-wired player for a playback request, or nil if not signed in. The platform
    /// engine + thumbnail source are injected by the app target (VLCKit is per-platform), so this
    /// shared factory owns only the brain wiring (unrestrict / progress / subtitles).
    public func makePlayer(for request: PlaybackRequest,
                           engine: VideoPlayerEngine) -> PlayerModel? {
        guard let torrents, let store = watchProgressStore else { return nil }
        // Playing a title claims it into the active profile's My List (add-or-play, rule ii).
        // Keyed by the title's id (matches the Detail toggle + My Library filter), not the
        // episode-level contentKey.
        if let myListStore, let pid = activeProfileID {
            let key = request.item.id
            Task { try? await myListStore.claim(profileID: pid, contentKey: key) }
        }
        let savePID = activeProfileID ?? ""
        let coordinator = PlaybackCoordinator(store: store, profileID: savePID)
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
                print("[resume] SAVE key=\(contentKey) profile=\(savePID) pos=\(position) dur=\(duration)")
                await coordinator.record(contentKey: contentKey, sourceKey: sourceKey,
                                         position: position, duration: duration)
            },
            subtitles: subtitlesProvider,
            details: detailsProvider,
            trackPreferences: trackPreferences)
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

    /// Durable on-disk location for caches we want to SURVIVE relaunches. tvOS aggressively purges
    /// `Caches/`, which evicted the library snapshot + OMDb ratings → a cold, blocking rebuild on
    /// nearly every launch. Application Support is not purged, so the snapshot sticks and the
    /// library renders instantly on relaunch.
    private static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? cachesDirectory
        return base.appending(path: "Seret", directoryHint: .isDirectory)
    }
}

/// No-op watch store for when SwiftData is unavailable — "For You" seeds then come from the
/// library only.
private struct NoWatch: WatchProgressProviding {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}
