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

    /// Backs the per-genre grids on Movies/Shows (nil while signed out).
    public private(set) var genreBrowsing: GenreBrowsing?

    /// Trailer-key resolver for the Add / Detail screens (nil while signed out).
    public private(set) var trailers: TrailerProviding?

    /// On-demand TMDB detail provider for the Detail screen (nil while signed out).
    public private(set) var detailsProvider: MediaDetailsProviding?

    /// Loads a person + their filmography. Nil while signed out — the TMDB client is built at
    /// sign-in, like every other provider here.
    public private(set) var personCredits: PersonCreditsProviding?

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
    // MARK: Watch state

    /// The on-device watch state, and the only backing there is. It outlived Trakt, which is
    /// exactly why it was built.
    public private(set) var localWatch: LocalWatchProvider?
    /// The same store `localWatch` wraps, for the one caller that must name the profile itself
    /// rather than have it resolved: the Letterboxd import refuses to run until the profile is
    /// known, and two sources of profile truth is what produced orphaned rows before.
    public private(set) var localWatchStore: LocalWatchStore?
    /// Profile roster store (CRUD) — used by the Who's-Watching / profile-manager UI (later slice).
    public private(set) var profileStore: ProfileStore?
    /// Per-profile "My List" store — claimed-title membership (later slice wires claim on add/play).
    public private(set) var myListStore: MyListStore?
    /// The user's chosen default version per title (CloudKit-synced alongside profiles).
    public private(set) var versionPreferences: VersionPreferenceStore?
    /// Device-local active-profile selection + roster (drives the Who's-Watching gate).
    public private(set) var activeProfiles: ActiveProfileStore?
    /// The profile this device is watching as (nil until resolved / while the gate is showing).
    public var activeProfileID: String? { activeProfiles?.activeProfileID }
    /// True when the Who's-Watching gate should show (more than one profile, none chosen here).
    public var needsProfileSelection: Bool { activeProfiles?.needsSelection ?? false }
    private var torrents: TorrentsClient?
    /// Short-TTL, one-shot cache of unrestricted URLs so Detail can warm the RD `unrestrict`
    /// call before Play is tapped (and the player can warm the next episode at Up Next).
    private var linkCache: PlayableLinkCache?
    /// Single, app-lifetime observer that rebuilds Home when CloudKit imports remote changes.
    private var remoteChangeObserver: NSObjectProtocol?
    /// The pending coalesced refresh for those changes — see `scheduleRemoteChangeRefresh`.
    private var remoteChangeTask: Task<Void, Never>?

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
        } catch {
            if Self.mustReauthenticate(after: error) { enterSignedOut() } else { enterSignedIn() }
        }
    }

    /// Whether a failed launch-time token check means the credentials are actually no good.
    ///
    /// Only two things do: there being none stored, and Real-Debrid rejecting the ones there are
    /// with a `401`. Everything else is Real-Debrid having a bad moment, and the stored credentials
    /// are still perfectly valid — so the launch stays optimistically signed in and later calls
    /// retry, exactly as it does when the device is offline.
    ///
    /// This used to treat ANY HTTP status as a rejection, which is wrong in the two ways that
    /// matter most in practice. Real-Debrid answers a rate limit with a bare `403` — this repo's
    /// own notes record that a tvOS client can get a PERSISTENT one — and it answers an outage with
    /// a `5xx`. Both signed the viewer out and made them sign in again, with nothing wrong with
    /// their account, and on an Apple TV that could repeat on every launch.
    nonisolated static func mustReauthenticate(after error: any Error) -> Bool {
        if error is RealDebridSessionError { return true }        // no stored credentials
        if case HTTPError.status(let code, _) = error { return code == 401 }
        return false                                              // transport, offline, decode
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
        personCredits = nil
        moviesBrowse = nil
        showsBrowse = nil
        genreBrowsing = nil
        trailers = nil
        detailsProvider = nil
        ratingsProvider = nil
        watchStore = nil
        home = nil
        torrents = nil
        linkCache = nil
        trailerResolver = nil
        streamSource = nil
        addService = nil
        downloadService = nil
        downloadsStore = nil
        downloadMonitor = nil
        downloadStore = nil
        subtitlesProvider = nil
        // The SwiftData-backed stores too. Every one of these holds the same CloudKit-mirrored
        // `ModelContainer`, and sign-in unconditionally builds a NEW one — so leaving them alive
        // meant signing out and back in left two containers open over the same store file, each
        // registering its own CloudKit sync. That is the hazard `purgeLegacyDefaultStore` was
        // written for, arrived at from the other direction.
        profileStore = nil
        myListStore = nil
        versionPreferences = nil
        activeProfiles = nil
        localWatch = nil
        localWatchStore = nil
        profileStoreMode = "none"
        state = .signedOut
    }

    /// The shared CloudKit container both Seret apps sync through (one private DB per Apple ID).
    private static let cloudKitContainerID = "iCloud.com.solomons.seret"

    /// The watch-progress + profile + My-List stores, built from ONE CloudKit-backed container so
    /// cascade-delete + owner migration work across them and they share a single private DB. Falls
    /// back to local-only if iCloud/CloudKit is unavailable so the app still works offline.
    private struct ProfileStores {
        let profiles: ProfileStore
        let myList: MyListStore
        let versions: VersionPreferenceStore
        let watch: LocalWatchStore
        let mode: String
    }

    /// Which backing store profiles use ("cloud", "local", "local-reset", or "none").
    public private(set) var profileStoreMode: String = "none"
    /// True when profiles are backed by CloudKit (syncing across this Apple ID's devices); false
    /// means a local-only store on this device (no iCloud account / CloudKit unavailable).
    public var profilesSyncedViaICloud: Bool { profileStoreMode == "cloud" }

    private static func makeProfileStores() -> ProfileStores? {
        let schema = Schema([Profile.self, MyListEntry.self, VersionPreference.self,
                             WatchProgress.self])
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
    ///
    /// Resolved through `WritableStorage`, which only returns a location it has actually created. This
    /// asked for Application Support directly, and on tvOS that cannot be created — so this
    /// returned nil on every Apple TV and both containers fell back to an IN-MEMORY store. Profiles,
    /// watch progress, My List, ratings and downloads were all discarded on every relaunch there.
    static func dedicatedStoreURL(_ name: String) -> URL? {
        WritableStorage.file(named: name)
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
        ProfileStores(
                      profiles: ProfileStore(modelContainer: container),
                      myList: MyListStore(modelContainer: container),
                      versions: VersionPreferenceStore(modelContainer: container),
                      watch: LocalWatchStore(modelContainer: container), mode: mode)
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

    /// bootstrap one for the (unauthenticated) token refresh call, and the authed one everything
    /// else uses. Safe to build even when unlinked/unconfigured — reads then just come back empty,
    /// which is the designed "not linked" degradation (Play instead of Resume, empty rails).
    /// Wire the watch stack. Local is the ONLY backing — Trakt was removed 2026-08-15, having been
    /// rejected by its own API since July; every provider seam it satisfied is satisfied by
    /// `LocalWatchProvider`, so nothing about what the app records or reads back changed.
    ///
    /// The profile resolver must spell a nil profile as "" — exactly what `LibraryStore` and
    /// `DetailStore` use — or reads miss writes.
    private func makeWatchStack(local: LocalWatchStore?) {
        localWatchStore = local
        localWatch = local.map { store in
            LocalWatchProvider(store: store,
                               profileID: { [weak self] in self?.activeProfileID ?? "" })
        }
        watchStore = localWatch
    }


    /// Key for the once-per-device flag guarding the legacy-progress hand-off.

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
        linkCache = PlayableLinkCache { link in
            let unrestricted = try await torrents.unrestrict(link: link)
            guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
            return url
        }
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
        profileStore = stores?.profiles
        myListStore = stores?.myList
        versionPreferences = stores?.versions
        profileStoreMode = stores?.mode ?? "none"
        // Local watch state is the source of truth and vends `watchStore` through the mirror, so
        // LibraryStore / HomeStore / DetailStore / the seed service consume the same seam
        // unchanged. Must come AFTER the stores above — it needs the local one.
        makeWatchStack(local: stores?.watch)
        libraryStore = LibraryStore(library: service, watch: watchStore,
                                    profileID: { [weak self] in self?.activeProfileID })
        searchStore = SearchStore(search: TMDBSearchService(client: tmdb))
        let discover = TMDBDiscoverService(client: tmdb)
        genreBrowsing = TMDBGenreService(client: tmdb)
        let seedService = RecommendationSeedService(
            watch: watchStore ?? NoWatch(), library: libraryStore,
            profileID: { [weak self] in self?.activeProfileID })
        moviesBrowse = DiscoverStore(kind: .movie, discover: discover, seeds: seedService)
        showsBrowse = DiscoverStore(kind: .show, discover: discover, seeds: seedService)
        trailers = TMDBTrailerService(client: tmdb)
        // Wrapped so a video is extracted once per session, never concurrently — YouTubeKit's local
        // extraction evaluates YouTube's player JS, and JavaScriptCore aborts the process outright
        // when its heap runs out. See `CachingTrailerStreamResolver`.
        trailerResolver = CachingTrailerStreamResolver(base: YouTubeKitStreamResolver())
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
            let dMonitor = DownloadMonitor(lister: torrents, store: dStore,
                                           resolver: TMDBDownloadIdentityResolver(search: tmdb))
            downloadsStore = dStore
            downloadMonitor = dMonitor
            // A finished download flips into the normal library — refresh so it appears + Play lights
            // up — and fires a "ready" notification. The status carries its own title, so this
            // works for a download started on another device as well as one of ours.
            let store = DownloadStore(service: dlService, records: dStore, poller: dMonitor,
                                      deleter: torrents,
                                      onReady: { [weak self] status in
                                          guard let self else { return }
                                          let name = status.title.isEmpty ? "Your download" : status.title
                                          // `reload()`, not `retry()`: the viewer is very likely
                                          // NOT on the library screen when a download finishes, and
                                          // bumping a counter no mounted view is watching left the
                                          // finished title out of the library until they opened it.
                                          self.libraryStore?.reload()
                                          self.downloadNotifier.notifyReady(title: name)
                                      })
            downloadStore = store
            Task { await store.loadActive() }
            Task { await downloadNotifier.requestAuthorization() }
        }
        detailsProvider = TMDBDetailsService(client: tmdb)
        personCredits = TMDBPersonService(client: tmdb)
        let omdbKey = Secrets.omdbAPIKey
        ratingsProvider = omdbKey.isEmpty ? nil
            : OMDbRatingsService(client: OMDbClient(apiKey: omdbKey),
                                 cache: OMDbRatingsCache(directory: Self.dataDirectory))
        // Home resumes playback directly, so it needs the same version preference the title page's
        // Play button uses — otherwise Continue Watching quietly plays a different file.
        home = watchStore.map { HomeStore(watch: $0, versionPrefs: versionPreferences) }
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
                // Adopt anything recorded before this resolved. Signing in does not wait for the
                // profile load, so a title played in that window records under no profile — and
                // every read afterwards uses the resolved id and misses it, which is a position
                // that exists but can never be read: "Play" instead of "Resume", from zero.
                if let owner = profiles.activeProfileID {
                    try? await self.localWatch?.adoptUnprofiledProgress(into: owner)
                }
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
            Task { @MainActor in self?.scheduleRemoteChangeRefresh() }
        }
    }

    /// Coalesce a burst of remote-change notifications into one refresh.
    ///
    /// CloudKit reports an import as a stream of per-batch notifications, so a sync that brings in
    /// a device's whole watch history fires many in quick succession — and each one used to run a
    /// roster fetch and a full Home rebuild on the main actor, every one of them thrown away by the
    /// next. Only the last notification in the window does the work now.
    private func scheduleRemoteChangeRefresh() {
        remoteChangeTask?.cancel()
        remoteChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // A CloudKit import can bring in a profile created on another device — refresh the
            // roster (without changing this device's selection) so it appears, then Home.
            await self?.activeProfiles?.reloadRoster()
            await self?.rebuildHome()
        }
    }

    /// A fresh grid store for one genre, or nil if not signed in. Deliberately not cached: a grid
    /// is a transient drill-down, and a cached one would show a stale page under a new sort.
    public func makeGenreGrid(kind: MediaKind, genre: DiscoverStore.Genre) -> GenreGridStore? {
        guard let genreBrowsing else { return nil }
        return GenreGridStore(kind: kind, genre: genre, browsing: genreBrowsing)
    }

    /// A fresh store for one person, or nil if not signed in. Not cached, for the same reason a
    /// genre grid is not: a person page is a transient drill-down, and a cached one would show a
    /// stale filmography.
    public func makePersonStore(for ref: TMDBPersonRef) -> PersonStore? {
        guard let personCredits else { return nil }
        return PersonStore(ref: ref, credits: personCredits)
    }

    /// Build a fully-wired player for a playback request, or nil if not signed in. The platform
    /// engine + thumbnail source are injected by the app target (VLCKit is per-platform), so this
    /// shared factory owns only the brain wiring (unrestrict / progress / subtitles).
    /// - Parameter audioProbe: measures the film's audio so a downloaded subtitle can be lined up
    ///   against it. Supplied by the app because only the app has libvlc; nil simply means the
    ///   auto-sync action is not offered.
    public func makePlayer(for request: PlaybackRequest,
                           engine: VideoPlayerEngine,
                           audioProbe: AudioLoudnessProbing? = nil) -> PlayerModel? {
        guard let torrents else { return nil }
        let watch = watchStore
        // Captured once: a player outlives a profile switch, and its progress must keep landing
        // under the profile that started the playback.
        //
        // …but only once there IS one. Capturing "" because the profile load had not finished yet
        // files the whole session's progress under no profile, where no later read can find it.
        // `profiles` is consulted only in that case, so a real capture still wins for the session.
        let capturedProfile = activeProfileID
        let profiles = activeProfiles
        /// The profile this session's progress belongs to: the captured one when there was one,
        /// otherwise whatever resolved since.
        let resolveProfile: @Sendable () async -> String = {
            if let capturedProfile { return capturedProfile }
            return await MainActor.run { profiles?.activeProfileID } ?? ""
        }
        // Playing a title claims it into the active profile's My List (add-or-play, rule ii).
        // Keyed by the title's id (matches the Detail toggle + My Library filter), not the
        // episode-level contentKey.
        if let myListStore, let pid = activeProfileID {
            let key = request.item.id
            Task { try? await myListStore.claim(profileID: pid, contentKey: key) }
        }
        let cache = linkCache
        return PlayerModel(
            request: request,
            engine: engine,
            // Through the link cache: a Detail-open prefetch makes this instant; otherwise it
            // resolves directly (consume is one-shot, so a retry always re-unrestricts fresh).
            unrestrict: { link in
                if let cache { return try await cache.consume(link) }
                let unrestricted = try await torrents.unrestrict(link: link)
                guard let url = URL(string: unrestricted.download) else { throw URLError(.badURL) }
                return url
            },
            // The 1s tick is what records playback.
            //
            // PlayerModel hands over the CURRENT contentKey + sourceKey, not the request's, so an
            // Up Next auto-advance records against the episode actually playing.
            recordProgress: { contentKey, sourceKey, position, duration in
                guard duration > 0 else { return }
                let target = await resolveProfile()
                try? await watch?.record(contentKey: contentKey, sourceKey: sourceKey,
                                         positionSeconds: position, durationSeconds: duration,
                                         finished: false, profileID: target)
            },
            subtitles: subtitlesProvider,
            details: detailsProvider,
            trackPreferences: trackPreferences,
            // Authoritative resume: the saved position is re-read at load time so playback can't
            // race the screen's own watch-state load, or resume from a stale hint.
            resolveResume: { key in
                let target = await resolveProfile()
                // One unwrap, not two: `try?` flattens the provider's optional return.
                guard let watch,
                      let saved = try? await watch.progress(forContentKey: key, profileID: target)
                else { return nil }
                return saved.resumePosition
            },
            // Up Next warm-up: resolve the next episode's link while the countdown runs.
            prefetchLink: { link in
                guard let cache else { return }
                Task { await cache.prefetch(link) }
            },
            // Declares our transport to the system: the iPhone Remote app's ±10s buttons and
            // scrubber, Control Center, Siri and HDMI-CEC TV remotes. Unavailable on macOS, where
            // this package only builds to run `swift test`.
            nowPlaying: Self.makeNowPlayingCenter(),
            audioProbe: audioProbe)
    }

    /// The system Now Playing surface, when the platform has MediaPlayer + UIKit (iOS/tvOS).
    /// nil on macOS so `swift test` keeps building.
    private static func makeNowPlayingCenter() -> NowPlayingControlling? {
        #if canImport(MediaPlayer) && canImport(UIKit)
        return NowPlayingCenter()
        #else
        return nil
        #endif
    }

    /// Warm the RD `unrestrict` for a source the user is likely to play next (fire-and-forget).
    /// Detail screens call this on open with the movie's best source / the show's next episode,
    /// so tapping Play starts with the playable URL already resolved. In-memory + short-TTL +
    /// one-shot — see `PlayableLinkCache`.
    public func prefetchPlayback(for source: MediaSource) {
        guard let linkCache else { return }
        Task { await linkCache.prefetch(source.restrictedLink) }
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

    /// The acquire-and-play engine for one title — what makes Play work on something you have not
    /// added. `imdbID` comes from the page's resolved TMDB details, so it is nil until those land;
    /// the engine reports "not signed in" until then rather than silently doing nothing.
    public func makeAcquisition(for item: MediaItem, imdbID: String?,
                                originalLanguage: String?) -> AcquisitionStore {
        AcquisitionStore(item: item) { [weak self] kind in
            guard let self, let imdbID else { return nil }
            return self.makeAddStore(imdbID: imdbID, kind: kind, originalLanguage: originalLanguage)
        }
    }

    /// The Letterboxd import. Nil until there is a watch store to write into.
    ///
    /// The library is read when the import RUNS, not when the model is built, so a refresh that
    /// adds titles is picked up by an import started afterwards. The film map is seeded from disk
    /// and written back, which is what makes slug resolution a one-time cost per film.
    public func makeLetterboxdImportModel(library: LibraryStore) -> LetterboxdImportModel? {
        guard let watchStore = localWatchStore else { return nil }

        let settingsStore = UbiquitousLetterboxdSettingsStore()
        settingsStore.synchronize()
        let mapStore = LetterboxdFilmMapStore(fileURL: LetterboxdFilmMapStore.defaultURL())

        return LetterboxdImportModel(settingsStore: settingsStore) { profileID, onProgress in
            let username = settingsStore.load().username
            let http = HTTPClient()
            let map = LetterboxdFilmMap(seed: mapStore.load())
            let importer = LetterboxdImporter(
                reader: LetterboxdProfileReader(http: http, username: username),
                resolver: LetterboxdFilmResolver(http: http, map: map),
                map: map,
                mapStore: mapStore,
                store: watchStore,
                resolveDelay: .milliseconds(400))
            let movies = await MainActor.run { library.movies }
            return try await importer.run(movies: movies, profileID: profileID, onProgress: onProgress)
        }
    }

    /// The Letterboxd watchlist. Nil until there is a library to mark owned films against.
    ///
    /// The syncer is built once and captured, so the entries and the resolved-id cache are shared
    /// by every appearance of the screen rather than rebuilt per navigation.
    /// `POST /api/letterboxd/watchlist` on the owner's SeretServer.
    ///
    /// A bare 2xx is the whole success contract; the server has already named any failure in its
    /// status, which `WatchlistRemovalRelay` turns into something a screen can say.
    private static func postWatchlistRemoval(to address: String, tmdbID: Int,
                                             http: HTTPClient) async throws {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare host or `host:port` is what someone types; make it a URL rather than failing.
        if !trimmed.lowercased().hasPrefix("http") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        guard let url = URL(string: trimmed + "/api/letterboxd/watchlist") else {
            throw URLError(.badURL)
        }
        try await http.postJSON(url, jsonBody: #"{"tmdbID":\#(tmdbID),"inWatchlist":false}"#)
    }

    public func makeWatchlistModel() -> WatchlistModel? {
        guard let library = libraryStore else { return nil }

        let settingsStore = UbiquitousLetterboxdSettingsStore()
        settingsStore.synchronize()
        let settings = settingsStore.load()
        let store = WatchlistStore(fileURL: WatchlistStore.defaultURL())
        let http = HTTPClient()
        let syncer = WatchlistSyncer(
            reader: LetterboxdProfileReader(http: http, username: settings.username),
            resolver: TMDBWatchlistTitleResolver(tmdb: TMDBClient(apiKey: Secrets.tmdbAPIKey)),
            store: store)

        // Letterboxd can only be written by a real browser, and only SeretServer has one, so a
        // removal made here is relayed to it. Failures leave the removal pending rather than
        // dropping it — see `WatchlistRemovalRelay`.
        let relay = WatchlistRemovalRelay(
            syncer: syncer,
            settings: { settingsStore.load() },
            post: { address, tmdbID in
                try await Self.postWatchlistRemoval(to: address, tmdbID: tmdbID, http: http)
            })

        let model = WatchlistModel(cached: store.load(), settings: settings,
                                   remove: { slug in await syncer.remove(slug: slug) },
                                   relay: { await relay.drain() }) { onProgress in
            try await syncer.sync(onProgress: onProgress)
        }
        model.ownedTMDBIDs = Set(library.movies.compactMap(\.tmdbID))
        return model
    }

    /// Watched marks for browse/search posters. One instance is shared by every grid, so switching
    /// tabs does not re-query what is already known.
    public func makeTileWatchMarks() -> TileWatchMarks {
        TileWatchMarks(watch: { [weak self] in self?.watchStore },
                       profileID: { [weak self] in self?.activeProfileID ?? "" })
    }

    /// Marks a whole series watched. Nil until there is a details provider and a watch store.
    public func makeShowWatchMarker() -> ShowWatchMarker? {
        guard let detailsProvider, let watchStore else { return nil }
        return ShowWatchMarker(details: detailsProvider, watch: watchStore)
    }

    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// The most durable on-disk location this platform will actually give us, for caches we want to
    /// SURVIVE relaunches — the library snapshot and the OMDb ratings.
    ///
    /// Application Support is preferred because `Caches` is purgeable, and tvOS purging it evicted
    /// the snapshot into a cold, blocking rebuild. But naming Application Support outright made
    /// this WORSE on the device it was meant to help: a tvOS container has no such directory, so
    /// the snapshot was never written at all and every launch rebuilt from scratch. `WritableStorage`
    /// hands back a directory it has proved it can create.
    private static var dataDirectory: URL {
        WritableStorage.directory(named: "Seret")
            ?? cachesDirectory.appending(path: "Seret", directoryHint: .isDirectory)
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
