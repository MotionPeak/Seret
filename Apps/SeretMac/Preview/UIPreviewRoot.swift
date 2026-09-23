#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG only: `-uiPreview <case>` boots straight into one screen with fixture data, so every screen
/// can be screenshot-verified without signing in or walking the UI (the tvOS lesson). Each task that
/// adds a screen adds its case here.
struct UIPreviewRoot: View {
    let target: String

    var body: some View {
        Group {
            switch target {
            case "vlcsmoke":
                VLCSmokePreview(url: VLCSmokePreview.url(from: ProcessInfo.processInfo.arguments))
            case "design":
                DesignGalleryPreview()
            case "splash":
                SplashView { }
            case "shell":
                MainShell(model: ShellModel(defaults: UserDefaults(suiteName: "seret.preview.shell")!))
            case "shellcollapsed":
                MainShell(model: {
                    let defaults = UserDefaults(suiteName: "seret.preview.shellcollapsed")!
                    defaults.set(true, forKey: "seret.mac.sidebarCollapsed")
                    return ShellModel(defaults: defaults)
                }())
            case "posters":
                PosterGalleryPreview()
            case "postersloading":
                PosterGalleryPreview(isLoading: true)
            case "rail":
                RailGalleryPreview()
            case "downloads":
                DownloadsPreviewHost(collapsedSidebar: false, popoverOnly: false)
            case "downloadsrail":
                DownloadsPreviewHost(collapsedSidebar: true, popoverOnly: false)
            case "downloadspopover":
                DownloadsPreviewHost(collapsedSidebar: false, popoverOnly: true)
            case "home":
                HomePreviewHost()
            case "homenohistory":
                HomePreviewHost(withHistory: false, includeDownloads: false)
            case "homeloading":
                HomePreviewHost(libraryMode: .loadingForever, includeDownloads: false)
            case "homeempty":
                HomePreviewHost(libraryMode: .empty, includeDownloads: false)
            case "library":
                libraryPreview(.items(Fixture.films + Fixture.shows))
            case "libraryshows":
                libraryPreview(.items(Fixture.films + Fixture.shows), forcedKind: .show)
            case "libraryloading":
                libraryPreview(.loadingForever)
            case "libraryempty":
                libraryPreview(.empty)
            case "libraryfailed":
                libraryPreview(.failing)
            case "toast":
                toastPreview(isFailure: false)
            case "toastfailure":
                toastPreview(isFailure: true)
            case "browse":
                BrowsePreviewHost()
            case "browseloading":
                BrowsePreviewHost(mode: .hanging)
            case "browsefailed":
                BrowsePreviewHost(mode: .failing)
            case "browseshows":
                BrowsePreviewHost(kind: .show)
            case "genre":
                BrowsePreviewHost(genre: DiscoverStore.genres(for: .movie).first { $0.name == "Drama" })
            case "titlenotowned":
                titleNotOwnedPreview()
            case "searchresults":
                SearchPreviewHost(mode: .results)
            case "searching":
                SearchPreviewHost(mode: .hanging)
            case "searchempty":
                SearchPreviewHost(mode: .empty)
            case "searchfailed":
                SearchPreviewHost(mode: .failing)
            case "titlemovie":
                titlePreview(item: Fixture.films[0])
            case "titleshow":
                titlePreview(item: Fixture.show)
            case "titleshows2":
                titlePreview(item: Fixture.show, selectSeason: 2)
            case "titlefinding":
                titleFindingPreview()
            case "titleratingsloading":
                titlePreview(item: Fixture.films[0], ratings: PreviewHangingRatings())
            case "titletrailer":
                titleTrailerPreview()
            case "trailerfull":
                trailerFullPreview()
            case "titlerated":
                titleRatedPreview()
            case "titledownload":
                TitleDownloadPreviewHost(phase: nil)
            case "titledownloading":
                TitleDownloadPreviewHost(phase: .downloading, fraction: 0.42)
            case "titledownloadfailed":
                TitleDownloadPreviewHost(phase: .failed("No seeders available right now."))
            case "titleversions":
                titleVersionsPreview()
            case "titlerails":
                titleRailsPreview()
            case "titlerailsloading":
                titleRailsLoadingPreview()
            case "person":
                personPreview(mode: .loaded)
            case "personloading":
                personPreview(mode: .hanging)
            case "personempty":
                personPreview(mode: .empty)
            case "personfailed":
                personPreview(mode: .failed)
            case "versionssheet":
                VersionsSheetPreviewHost(mode: .list)
            case "versionsloading":
                VersionsSheetPreviewHost(mode: .hangingStreams)
            case "versionspicking":
                VersionsSheetPreviewHost(mode: .hangingAdd, autoPickFirst: true)
            case "magnetvalid":
                MagnetSheetPreviewHost(prefill: "magnet:?xt=urn:btih:c9e15763f722f23e98a29decdfae341b98d53056&dn=The.Godfather.1972.2160p.BluRay.x265")
            case "magnetinvalid":
                MagnetSheetPreviewHost(prefill: "not a magnet link")
            case "playerloading":
                // `PlayerScreen`'s own `.onAppear` calls `model.start()`; a hanging unrestrict keeps
                // it stuck in `.preparing` so the cold-open overlay stays on screen.
                PlayerPreviewHost(driver: PlayerPreviewDriver(hangs: true), action: .none)
            case "playerfailed":
                // Likewise: `.onAppear` alone drives the (failing) load to `.failed`.
                PlayerPreviewHost(driver: PlayerPreviewDriver(failing: true), action: .none)
            case "player":
                PlayerPreviewHost(driver: PlayerPreviewDriver(), action: .prime)
            case "playerpaused":
                PlayerPreviewHost(driver: PlayerPreviewDriver(), action: .primeThenPause)
            case "playertracks":
                PlayerPreviewHost(driver: PlayerPreviewDriver(), action: .primeWithTracksOpen)
            case "playerfullscreen":
                PlayerPreviewHost(driver: PlayerPreviewDriver(), action: .prime, startsFullScreen: true)
            case "playerupnext":
                let upNextEpisode = Fixture.show.seasons.first { $0.number == 1 }!.episodes.first { $0.number == 1 }!
                PlayerPreviewHost(driver: PlayerPreviewDriver(item: Fixture.show, episode: upNextEpisode),
                                 action: .primeNearEpisodeEnd)
            case "shellnav":
                MainShell(model: {
                    let model = ShellModel(defaults: UserDefaults(suiteName: "seret.preview.shellnav")!)
                    model.select(.library)
                    model.open(.title(MediaItem(id: "movie:tmdb:1", kind: .movie, title: "Preview Title",
                                                year: 2024, sources: [], seasons: [])))
                    return model
                }())
            case "signincode":
                signIn(.code(userCode: "W6XD2P7N", verificationURL: URL(string: "https://real-debrid.com/device"),
                             expiresIn: 600), mode: .code)
            case "signintoken":
                signIn(.token(checking: false, error: nil), mode: .token)
            case "signintokenerror":
                signIn(.token(checking: false, error: "That token wasn't accepted by Real-Debrid. Check it and try again."),
                       mode: .token)
            case "signinfailed":
                signIn(.failed("Real-Debrid is busy right now. Wait a minute and try again."), mode: .code)
            case "signinpreparing":
                signIn(.preparing("Preparing sign-in…"), mode: .code)
            default:
                Text("Unknown -uiPreview case: \(target)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Matches the app's own `.defaultSize` (1440×900): the player's tracks panel and Up Next
        // card sit close to the trailing edge, and a narrower preview window (the 1100×700 minimum
        // alone) clipped their content against the window's own right edge — invisible in a
        // screenshot despite rendering correctly, since `screencapture -l<windowID>` can only ever
        // capture what is actually inside the window's bounds.
        .frame(minWidth: 1440, minHeight: 900)
        .preferredColorScheme(.dark)
    }

    private func signIn(_ panel: SignInScreenState.Panel, mode: SignInMode) -> some View {
        SignInPreviewHost(state: SignInScreenState(panel: panel), mode: mode)
    }

    /// Mounts `MainShell` on `.library` with a fixture `LibraryStore` injected into the
    /// environment — the same seam `LibraryRoot` reads before falling back to the session.
    private func libraryPreview(_ mode: PreviewLibrary.Mode, forcedKind: MediaKind? = nil) -> some View {
        let suite = "seret.preview.library.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        let store = LibraryStore(library: PreviewLibrary(mode: mode), watch: PreviewWatch(Fixture.watch),
                                 profileID: { "" })
        return MainShell(model: model)
            .environment(store)
            .environment(\.previewForcedLibraryKind, forcedKind)
    }

    /// Mounts `MainShell` on `.library` with a fixture library and the toast already pinned
    /// (`lingers: nil`) so the screenshot never races the fade.
    private func toastPreview(isFailure: Bool) -> some View {
        let suite = "seret.preview.toast.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        let store = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + Fixture.shows)),
                                 watch: PreviewWatch(Fixture.watch), profileID: { "" })
        model.showToast(isFailure
            ? "Couldn\u{2019}t remove \u{201C}The Lord of the Rings: The Fellowship of the Ring\u{201D}. Please try again."
            : "Added to your Letterboxd watchlist",
            isFailure: isFailure, lingers: nil)
        return MainShell(model: model)
            .environment(store)
    }

    /// Mounts `MainShell` on `.library` with the title already pushed (the real navigation path a
    /// poster click takes) and a fixture `DetailStore` injected — the same seam `TitleRoute` reads
    /// before falling back to the session. `acquireMode` injects a `TitleAcquirer` over
    /// `PreviewAcquireSource`, the same seam `TitlePage` reads before building its own.
    private func titlePreview(item: MediaItem, selectSeason: Int? = nil,
                              ratings: RatingsProviding = PreviewRatings(),
                              letterboxd: LetterboxdRatingProviding = PreviewLetterboxd(),
                              acquireMode: PreviewAcquireMode? = nil) -> some View {
        let suite = "seret.preview.title.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch),
                                profileID: "", ratings: ratings, letterboxd: letterboxd)
        return Group {
            if let acquireMode {
                MainShell(model: model)
                    .environment(store)
                    .environment(makePreviewAcquirer(item: item, mode: acquireMode))
            } else {
                MainShell(model: model)
                    .environment(store)
            }
        }
        .task {
            if let selectSeason { await store.selectSeason(selectSeason) }
        }
    }

    /// `-uiPreview titlenotowned` — `MainShell` on `.movies` with `.title(.placeholder(for:))`
    /// pushed for a title the fixture library does NOT own (Decision 2). `PreviewDetails` gives
    /// 693134 (Dune: Part Two) its real imdbID, so once details resolve the hero's acquire button
    /// reads an enabled gold "Play" rather than the disabled M2 "Not in Your Library".
    private func titleNotOwnedPreview() -> some View {
        let suite = "seret.preview.titlenotowned.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.movies)
        let hit = SearchHit(result: TMDBSearchResult(id: 693134, title: "Dune: Part Two", name: nil,
                                                     releaseDate: "2024-01-01", firstAirDate: nil,
                                                     posterPath: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg",
                                                     overview: nil, voteAverage: 8.2), kind: .movie)
        let item = MediaItem.placeholder(for: hit)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        return MainShell(model: model)
            .environment(store)
            .environment(makePreviewAcquirer(item: item, mode: .instant))
    }

    /// `-uiPreview titlefinding` — the same not-owned Dune page, but the acquirer's stream source
    /// hangs forever, and Play is auto-tapped once details resolve — pinning the busy "Finding a
    /// version…" state (icon pulsing, button disabled) for a screenshot.
    private func titleFindingPreview() -> some View {
        let suite = "seret.preview.titlefinding.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.movies)
        let hit = SearchHit(result: TMDBSearchResult(id: 693134, title: "Dune: Part Two", name: nil,
                                                     releaseDate: "2024-01-01", firstAirDate: nil,
                                                     posterPath: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg",
                                                     overview: nil, voteAverage: 8.2), kind: .movie)
        let item = MediaItem.placeholder(for: hit)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        let acquirer = makePreviewAcquirer(item: item, mode: .hanging)
        return MainShell(model: model)
            .environment(store)
            .environment(acquirer)
            .task {
                await store.load()
                Task { _ = await acquirer.play(.movie) }
            }
    }

    /// `-uiPreview titletrailer` — the owned Dune page with a fixture `TrailerModel` that resolves
    /// immediately and a near-zero autoplay delay, so the inline loop starts and both capsules
    /// show without a screenshot waiting out the real 4 s.
    private func titleTrailerPreview() -> some View {
        titlePreview(item: Fixture.films[0])
            .environment(makePreviewTrailerModel())
            .environment(\.previewTrailerDelay, .milliseconds(1))
    }

    /// `-uiPreview trailerfull` — `MainShell` with the full-window trailer already pinned, the same
    /// way a title page's own `presentTrailer` would leave it.
    private func trailerFullPreview() -> some View {
        let suite = "seret.preview.trailerfull.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.presentTrailer(PreviewTrailerSource.url, title: "Dune: Part Two")
        return MainShell(model: model)
    }

    /// `-uiPreview titlerated` — the owned Dune page with a personal rating and history already on
    /// record, so "YOUR RATING" shows 8 gold stars, "8/10" and both history lines.
    private func titleRatedPreview() -> some View {
        let item = Fixture.films[0]
        let watch = PreviewWatch(Fixture.watch, ratings: [item.id: 8],
                                 summaries: [item.id: WatchSummary(plays: 2, lastWatchedAt: Date(timeIntervalSince1970: 1_722_600_000))],
                                 since: [item.id: Date(timeIntervalSince1970: 1_705_000_000)])
        let suite = "seret.preview.titlerated.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: watch, profileID: "",
                                ratings: PreviewRatings(), letterboxd: PreviewLetterboxd())
        return MainShell(model: model).environment(store)
    }

    /// `-uiPreview titleversions` — the owned, three-version Godfather page with the BluRay row
    /// (index 1) marked preferred via a fixed `PreviewVersionPrefs`, so ✓ lands there rather than
    /// wherever the ranker would put it.
    private func titleVersionsPreview() -> some View {
        let item = Fixture.filmWithVersions
        let suite = "seret.preview.titleversions.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let preferredKey = WatchKey.source(item.sources[1])
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch),
                                profileID: "", versionPrefs: PreviewVersionPrefs(sourceKey: preferredKey))
        return MainShell(model: model).environment(store)
    }

    /// `-uiPreview titlerails` — the owned Dune page scrolled to its rails, with a fixture
    /// `LibraryStore` injected (unlike the other title cases) so the franchise rail's "Dune" part —
    /// owned, but not the one you're reading — shows M2's owned disc, not just Part Two's ring.
    /// "Dune" (438631) is added to the fixture library here alone, not to `Fixture.films` itself,
    /// so every other screen's stable ordering is untouched.
    private func titleRailsPreview() -> some View {
        let item = Fixture.films[0]
        let dune = MediaItem(id: "movie:tmdb:438631", kind: .movie, title: "Dune", year: 2021,
                             sources: [Fixture.source(id: "t438631")], seasons: [], tmdbID: 438631,
                             posterPath: "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg",
                             backdropPath: "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg", addedAt: .now)
        let suite = "seret.preview.titlerails.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        let library = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + [dune] + Fixture.shows)),
                                   watch: PreviewWatch(Fixture.watch), profileID: { "" })
        let watchActor = PreviewWatch(Fixture.watch)
        let marks = TileWatchMarks(watch: { watchActor }, profileID: { "" })
        return MainShell(model: model)
            .environment(store)
            .environment(library)
            .environment(marks)
            .environment(\.previewScrollToBottom, true)
    }

    /// `-uiPreview titlerailsloading` — the owned Dune page with a details call that never
    /// resolves, so `richState` stays `.loading` and the rail skeletons stay on screen.
    private func titleRailsLoadingPreview() -> some View {
        let item = Fixture.films[0]
        let suite = "seret.preview.titlerailsloading.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        model.open(.title(item))
        let store = DetailStore(item: item, details: PreviewHangingDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        return MainShell(model: model)
            .environment(store)
            .environment(\.previewScrollToBottom, true)
    }

    /// `-uiPreview person` / `personloading` / `personempty` / `personfailed` — a `PersonRoute`
    /// pushed on `.library` with a fixture `PersonStore` injected, the same seam production reads
    /// before building one from the session.
    private func personPreview(mode: PreviewPersonMode) -> some View {
        let suite = "seret.preview.person.\(UUID().uuidString)"
        let model = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        model.select(.library)
        let ref = TMDBPersonRef(id: 137427, name: "Denis Villeneuve")
        model.open(.person(ref))
        let store = PersonStore(ref: ref, credits: PreviewPersonCredits(mode: mode))
        let library = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + Fixture.shows)),
                                   watch: PreviewWatch(Fixture.watch), profileID: { "" })
        return MainShell(model: model)
            .environment(library)
            .environment(store)
    }
}

/// `-uiPreview titledownload` / `titledownloading` / `titledownloadfailed` — the not-owned Dune
/// page with the film download section in each of its states, all at the same section height.
/// A dedicated host (not a plain function) because the tracked `DownloadStatus` fixture and the
/// `TitleAcquirer` it feeds both need an async build before the page can show the right state.
private struct TitleDownloadPreviewHost: View {
    let phase: DownloadStatus.Phase?
    var fraction: Double = 0

    private let item: MediaItem
    @State private var model: ShellModel
    @State private var store: DetailStore
    @State private var acquirer: TitleAcquirer?

    init(phase: DownloadStatus.Phase?, fraction: Double = 0) {
        self.phase = phase
        self.fraction = fraction
        let hit = SearchHit(result: TMDBSearchResult(id: 693134, title: "Dune: Part Two", name: nil,
                                                     releaseDate: "2024-01-01", firstAirDate: nil,
                                                     posterPath: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg",
                                                     overview: nil, voteAverage: 8.2), kind: .movie)
        let item = MediaItem.placeholder(for: hit)
        self.item = item
        _model = State(initialValue: ShellModel(defaults: UserDefaults(suiteName: "seret.preview.titledownload.\(UUID().uuidString)")!))
        _store = State(initialValue: DetailStore(item: item, details: PreviewDetails(),
                                                 watch: PreviewWatch(Fixture.watch), profileID: ""))
    }

    var body: some View {
        MainShell(model: model)
            .environment(store)
            .environment(acquirer ?? makePreviewAcquirer(item: item, mode: .none))
            .task {
                model.select(.movies)
                model.open(.title(item))
                var downloads: DownloadStore?
                if let phase {
                    downloads = await PreviewDownloads.store(forMovieTmdbID: 693134, title: item.title,
                                                             posterPath: item.posterPath, phase: phase,
                                                             fraction: fraction)
                }
                acquirer = makePreviewAcquirer(item: item, mode: .none, downloads: downloads)
            }
    }
}

/// `-uiPreview versionssheet` / `versionsloading` / `versionspicking` — the Versions sheet's
/// content rendered inline (Decision 7: a real `.sheet` is a separate window the capture script
/// cannot see) over `MainShell`'s own title page, so the shot still shows the app's chrome around
/// it. `mode` drives `PreviewVersionsSource`; `autoPickFirst` fires an unawaited pick at the first
/// (hanging) release right after load, pinning "Starting…" for `versionspicking`.
private struct VersionsSheetPreviewHost: View {
    let mode: PreviewVersionsSourceMode
    var autoPickFirst = false

    @State private var model: VersionsModel?

    private static let hit = SearchHit(result: TMDBSearchResult(
        id: 693134, title: "Dune: Part Two", name: nil, releaseDate: "2024-01-01", firstAirDate: nil,
        posterPath: "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", overview: nil, voteAverage: 8.2), kind: .movie)

    var body: some View {
        let suite = "seret.preview.versionssheet.\(UUID().uuidString)"
        let shellModel = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        shellModel.select(.movies)
        let item = MediaItem.placeholder(for: Self.hit)
        shellModel.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        return MainShell(model: shellModel)
            .environment(store)
            .overlay {
                if let model {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VersionsSheet(model: model, onPlay: { _ in }, onClose: {})
                }
            }
            .task {
                let source = PreviewVersionsSource(mode: mode)
                let flow = AddFlowStore(hit: Self.hit, details: PreviewDetails(),
                                        streamSource: source, add: source)
                let m = VersionsModel(hit: Self.hit, target: .movie, flow: flow, downloads: nil, onAdded: {})
                model = m
                await m.load()
                if autoPickFirst, let first = PreviewVersionsSource.releases().first {
                    Task { _ = await m.pick(first) }
                }
            }
    }
}

/// `-uiPreview magnetvalid` / `magnetinvalid` — the Magnet sheet's content rendered inline over
/// `MainShell`'s own title page, `text` prefilled so the validation line is already showing.
private struct MagnetSheetPreviewHost: View {
    let prefill: String

    var body: some View {
        let suite = "seret.preview.magnetsheet.\(UUID().uuidString)"
        let shellModel = ShellModel(defaults: UserDefaults(suiteName: suite)!)
        shellModel.select(.library)
        let item = Fixture.filmWithVersions
        shellModel.open(.title(item))
        let store = DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatch(Fixture.watch), profileID: "")
        let downloads = DownloadStore(service: PreviewNeverDownloads(), records: PreviewNoRecords(),
                                      poller: PreviewNoPoll(), deleter: PreviewNoDelete())
        let model = MagnetAddModel(target: DownloadTarget.movie(item)!.magnet, downloads: downloads)
        return MainShell(model: shellModel)
            .environment(store)
            .overlay {
                Color.black.opacity(0.45).ignoresSafeArea()
                MagnetSheet(model: model, title: item.title, onDone: {}, initialText: prefill)
            }
    }
}

private struct PreviewNeverDownloads: DownloadRequesting {
    func startDownload(infoHash: String) async throws -> TorrentInfo { throw URLError(.badServerResponse) }
}
private struct PreviewNoRecords: DownloadRecording {
    func upsert(_ data: DownloadRequestData) async throws {}
    func all() async throws -> [DownloadRequestData] { [] }
    func delete(torrentID: String) async throws {}
}
private struct PreviewNoPoll: DownloadPolling {
    func poll() async throws -> [DownloadStatus] { [] }
}
private struct PreviewNoDelete: DownloadDeleting {
    func deleteTorrent(id: String) async throws {}
}

/// Mounts `PlayerScreen` directly (not through `MainShell`/`ShellModel`) over a `PlayerPreviewDriver`
/// — the fixture film's backdrop stands in for the video surface, a still frame to judge the HUD
/// against. `PlayerScreen`'s own `.onAppear` already calls `model.start()`, so `.none` is enough for
/// `playerloading`/`playerfailed` (the driver's `hangs`/`failing` decide what that load does). Every
/// other action runs the driver's priming sequence over a PINNED `HUDVisibility(delay: nil)`, so the
/// HUD can never auto-hide out from under a screenshot taken a few seconds after launch.
private struct PlayerPreviewHost: View {
    enum Action: Equatable { case none, prime, primeThenPause, primeWithTracksOpen, primeNearEpisodeEnd }
    @State var driver: PlayerPreviewDriver
    let action: Action
    /// Forces the compact full-screen HUD (spec §7.2) without a real `NSWindow` transition.
    var startsFullScreen: Bool = false

    private var startsWithTracksOpen: Bool { action == .primeWithTracksOpen }
    private var lockedWindowRef: WindowRef {
        let ref = WindowRef()
        if startsFullScreen { ref.lockFullScreen(true) }
        return ref
    }

    var body: some View {
        PlayerScreen(model: driver.model, onClose: {}, hud: HUDVisibility(delay: nil),
                    tracksPanelOpen: startsWithTracksOpen, windowRef: lockedWindowRef) {
            RemoteImage(url: TMDBClient.imageURL(path: Fixture.films[0].backdropPath, size: "w1280"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .task {
            switch action {
            case .none:
                break
            case .prime:
                await driver.prime()
            case .primeThenPause:
                await driver.prime()
                driver.model.pause()
            case .primeWithTracksOpen:
                await driver.prime(selectAudioTrackID: "audio/0")
            case .primeNearEpisodeEnd:
                await driver.primeNearEpisodeEnd()
            }
        }
    }
}

/// `-uiPreview rail` — a `PosterRail` (one card forced-hovered, the pager forced on), a
/// `LandscapeCard` rail, and a `RailSkeleton` of each size, all starting at the page inset.
private struct RailGalleryPreview: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    PosterRail(title: "Trending", items: Fixture.films, previewShowsPager: true) { item in
                        PosterTile(model: .library(item),
                                  state: PosterTileState(badge: WatchBadge(Fixture.watch[WatchKey.content(forMovie: item)])),
                                  actions: .make(kind: .movie, owned: true, watched: false, onWatchlist: false),
                                  perform: { _, _ in },
                                  forcedPointer: item.id == Fixture.films[2].id ? UnitPoint(x: 0.5, y: 0.5) : nil)
                    }
                    landscapeRail
                    RailSkeleton(cardSize: PosterCard.posterSize, count: 7)
                    RailSkeleton(cardSize: LandscapeCard.artSize, count: 5)
                }
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
        }
        .environment(\.pageLeadingInset, SidebarMetrics.contentLeading(collapsed: false))
        .frame(minWidth: 1440, minHeight: 900)
    }

    private var landscapeRail: some View {
        PosterRail(title: "Continue Watching", items: Fixture.films.prefix(4).map { $0 },
                   cardHeight: LandscapeCard.artSize.height) { item in
            LandscapeCard(title: item.title, caption: item.year.map(String.init) ?? "",
                         imageURL: TMDBClient.imageURL(path: item.backdropPath, size: "w780"),
                         fraction: 0.42, highlighted: item.id == Fixture.films[0].id)
        }
    }
}

/// `-uiPreview browse` / `browseloading` / `browsefailed` / `browseshows` / `genre` — `MainShell`
/// on `.movies`/`.shows` with a fixture `BrowseSources` injected via `\.previewBrowse` (the same
/// seam `BrowseRoot` reads before falling back to the session), plus the fixture library and marks
/// every poster needs for its owned/watched/CAM badges.
private struct BrowsePreviewHost: View {
    var kind: MediaKind = .movie
    var mode: PreviewDiscover.Mode = .normal
    var genre: DiscoverStore.Genre? = nil

    var body: some View {
        let suite = "seret.preview.browse.\(UUID().uuidString)"
        let model: ShellModel = {
            let m = ShellModel(defaults: UserDefaults(suiteName: suite)!)
            m.select(kind == .movie ? .movies : .shows)
            if let genre { m.setBrowseGenre(genre, for: kind) }
            return m
        }()
        let library = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + Fixture.shows)),
                                   watch: PreviewWatch(Fixture.watch), profileID: { "" })
        let sources = BrowseSources(movies: DiscoverStore(kind: .movie, discover: PreviewDiscover(mode: mode)),
                                    shows: DiscoverStore(kind: .show, discover: PreviewDiscover(mode: mode)),
                                    makeGenreGrid: { k, g in GenreGridStore(kind: k, genre: g, browsing: PreviewGenres()) })
        let watchActor = PreviewWatch(Fixture.watch)
        let marks = TileWatchMarks(watch: { watchActor }, profileID: { "" })
        return MainShell(model: model)
            .environment(library)
            .environment(marks)
            .environment(\.previewBrowse, sources)
    }
}

/// `-uiPreview searchresults` / `searching` / `searchempty` / `searchfailed` — `MainShell` on
/// `.home` with the query already set through `ShellModel.setSearchQuery` (the real path a
/// keystroke takes, so `.search` is genuinely on the path and the ‹ capsule appears), a fixture
/// `SearchStore` injected via `\.searchStore`, plus the fixture library and marks every result tile
/// needs for its owned/watched badges.
private struct SearchPreviewHost: View {
    let mode: PreviewSearch.Mode

    /// Built once — built in `body`, every re-render made a fresh shell, library and store.
    @State private var fixture: (model: ShellModel, library: LibraryStore, marks: TileWatchMarks)?
    @State private var store: SearchStore?

    var body: some View {
        if let fixture, let store {
            MainShell(model: fixture.model)
                .environment(fixture.library)
                .environment(fixture.marks)
                .environment(\.searchStore, store)
        } else {
            Color.clear.onAppear {
                let model = ShellModel(defaults: UserDefaults(suiteName: "seret.preview.search.\(UUID().uuidString)")!)
                model.select(.home)
                model.setSearchQuery("the")
                let library = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + Fixture.shows)),
                                           watch: PreviewWatch(Fixture.watch), profileID: { "" })
                let watchActor = PreviewWatch(Fixture.watch)
                fixture = (model, library, TileWatchMarks(watch: { watchActor }, profileID: { "" }))
                store = SearchStore(search: PreviewSearch(mode: mode))
            }
        }
    }
}

/// `-uiPreview downloads` / `downloadsrail` / `downloadspopover` — `MainShell` on `.library` with
/// the fixture library and `PreviewDownloads.store()` injected (built asynchronously, so this
/// waits for it before mounting the shell). `popoverOnly` renders `DownloadsPopover` alone,
/// centred on the canvas (Decision 14 — a real `.popover` is a separate window the capture script
/// cannot see).
private struct DownloadsPreviewHost: View {
    let collapsedSidebar: Bool
    let popoverOnly: Bool

    @State private var downloadStore: DownloadStore?
    @State private var libraryStore = LibraryStore(library: PreviewLibrary(mode: .items(Fixture.films + Fixture.shows)),
                                                    watch: PreviewWatch(Fixture.watch), profileID: { "" })

    var body: some View {
        Group {
            if let downloadStore {
                if popoverOnly {
                    ZStack {
                        CanvasBackground()
                        DownloadsPopover(tiles: downloadStore.activeTiles, library: libraryStore) { _ in }
                    }
                } else {
                    let suite = "seret.preview.downloads.\(UUID().uuidString)"
                    let model: ShellModel = {
                        let defaults = UserDefaults(suiteName: suite)!
                        defaults.set(collapsedSidebar, forKey: "seret.mac.sidebarCollapsed")
                        let m = ShellModel(defaults: defaults)
                        m.select(.library)
                        return m
                    }()
                    MainShell(model: model)
                        .environment(libraryStore)
                        .environment(downloadStore)
                }
            } else {
                CanvasBackground()
            }
        }
        .task { downloadStore = await PreviewDownloads.store() }
    }
}

/// `-uiPreview home` / `homenohistory` / `homeloading` / `homeempty` — `MainShell` on `.home`
/// with a fixture `LibraryStore` and `HomeStore` injected (`PreviewDownloads.store()` too, when
/// `includeDownloads`). Built asynchronously in `.task` (the library store and, for `home`, the
/// downloads store), same as `DownloadsPreviewHost`. `HomeScreen`'s own `.task`/`onChange` rebuild
/// `HomeStore` once `MainShell`'s injected `LibraryStore` finishes loading — the same reactive path
/// a real session drives, not a harness shortcut.
private struct HomePreviewHost: View {
    var libraryMode: PreviewLibrary.Mode = .items(Fixture.films + Fixture.shows)
    var withHistory: Bool = true
    var includeDownloads: Bool = true

    @State private var library: LibraryStore?
    @State private var home: HomeStore?
    @State private var downloadStore: DownloadStore?

    var body: some View {
        Group {
            if let library, let home {
                let suite = "seret.preview.home.\(UUID().uuidString)"
                let model: ShellModel = {
                    let m = ShellModel(defaults: UserDefaults(suiteName: suite)!)
                    m.select(.home)
                    return m
                }()
                shellView(model: model, library: library, home: home)
            } else {
                CanvasBackground()
            }
        }
        .task {
            if includeDownloads { downloadStore = await PreviewDownloads.store() }
            let homeStore = HomeStore(watch: PreviewWatch(withHistory ? Fixture.watch : [:]))
            homeStore.activeProfileID = "preview"
            home = homeStore
            library = LibraryStore(library: PreviewLibrary(mode: libraryMode),
                                   watch: PreviewWatch(Fixture.watch), profileID: { "" })
        }
    }

    @ViewBuilder
    private func shellView(model: ShellModel, library: LibraryStore, home: HomeStore) -> some View {
        if let downloadStore {
            MainShell(model: model).environment(library).environment(home).environment(downloadStore)
        } else {
            MainShell(model: model).environment(library).environment(home)
        }
    }
}

/// Holds the bindings a static sign-in state needs, and loads the real poster mosaic.
private struct SignInPreviewHost: View {
    let state: SignInScreenState
    @State var mode: SignInMode
    @State private var token = ""
    @State private var posters: [URL] = []

    var body: some View {
        SignInScreen(state: state, mode: $mode, token: $token, posters: posters)
            .task { posters = await PosterMosaic.loadPopularPosters() }
    }
}
#endif
