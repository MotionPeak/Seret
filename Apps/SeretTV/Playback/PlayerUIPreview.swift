#if DEBUG
import SwiftUI
import DebridUI
import DebridCore

/// DEBUG-only visual harnesses for player overlays. The tvOS simulator accepts no reliable
/// synthesized input, so the live player screen can't be driven there; these boot straight to a
/// target view so its layout can be screenshot-verified.
///
/// Launch with `-uiPreview <target>`, where target is:
///   - `scrubbar`  — the transport bar in each of its states
///   - `settings`  — the playback settings panel with grouped subtitle tracks
///   - `subtitles` — the full subtitle browser with ranked, badged results
///   - `subtitlesfailed` — the same browser after a pick that could not be honoured
///   - `detail`    — the Movie Detail page with a rating-capable stub store
///   - `sidemenu`  — the side menu EXPANDED over a stand-in page
///   - `sidemenucollapsed` — the same menu at rest, for an A/B of the two states
///   - `opensubtitles` — the OpenSubtitles pairing card: QR, LAN address, keyboard fallback
///   - `gridfade`  — a pre-scrolled grid under a pinned header, for tuning the top fade
///   - `person`    — the person page: header, As Actor / As Director, ranked credits
///
/// Not compiled into release builds.
struct PlayerUIPreview: View {
    let target: String

    var body: some View {
        switch target {
        case "settings":   SettingsPanelPreview()
        case "subtitles":  SubtitleBrowserPreview()
        case "subtitlesfailed": SubtitleBrowserPreview(failing: true)
        case "inputprobe": InputProbePreview()
        case "detail":     MovieDetailPreview()
        case "sidemenu":            SideMenuPreview(startExpanded: true)
        case "sidemenucollapsed":   SideMenuPreview(startExpanded: false)
        case "opensubtitles":       OpenSubtitlesPreview()
        case "gridfade":            GridTopFadePreview()
        case "person":              PersonScreenPreview()
        case "episodeversions":     EpisodeVersionsPreview()
        case "versions":            VersionListPreview()
        default:           ScrubBarPreview()
        }
    }
}

// MARK: - Version list

/// The real `VersionList` on fabricated streams, so the "Larger files" / "Recommended" split can be
/// screenshot-verified without a session, a search round-trip, or the focus engine.
///
/// The fixture is deliberately the shape that prompted the change: a handful of oversized REMUXes
/// that the ranking pushes to the bottom, mixed with sensible releases. It also proves the split
/// itself, since the sections are computed by `splitOversized` here exactly as in the screen.
private struct VersionListPreview: View {
    private static func stream(_ name: String, _ gb: Double, _ res: String,
                               _ source: String, cached: Bool) -> CachedStream {
        CachedStream(infoHash: name, fileIdx: nil, rawTitle: name,
                     parsed: ParsedRelease(title: "Sherlock", resolution: res, source: source),
                     languages: ["en"], sizeBytes: Int(gb * 1_000_000_000),
                     sourceName: "RD", isCached: cached)
    }

    private static let all: [CachedStream] = [
        stream("Sherlock.2160p.REMUX.HDR", 78, "2160p", "REMUX", cached: true),
        stream("Sherlock.2160p.REMUX.SDR", 64, "2160p", "REMUX", cached: false),
        stream("Sherlock.2160p.BluRay.x265", 41, "2160p", "BluRay", cached: true),
        stream("Sherlock.2160p.WEB-DL.x265", 22, "2160p", "WEB-DL", cached: true),
        stream("Sherlock.1080p.BluRay.x264", 12, "1080p", "BluRay", cached: true),
        stream("Sherlock.1080p.WEB-DL.x265", 6, "1080p", "WEB-DL", cached: false),
        stream("Sherlock.720p.BluRay.x264", 3, "720p", "BluRay", cached: true),
    ]

    var body: some View {
        let split = Self.all.splitOversized(episodesInSeason: nil)
        ScrollView {
            VersionList(larger: split.larger, rest: split.rest, picking: nil, onPick: { _ in })
                .padding(.horizontal, 60).padding(.vertical, 40)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Person page

/// The real `PersonScreen` on a fake credits provider, so the header, the two role sections and
/// the grid's focus geometry can be screenshot-verified without a session or a network.
///
/// The fake deliberately includes a "Self" credit and a Producer credit — neither should appear,
/// which makes this a visual check on the DebridCore ranking as well as on the layout.
private struct PersonScreenPreview: View {
    private static let ref = TMDBPersonRef(id: 1234, name: "Denis Villeneuve")

    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        NavigationStack {
            PersonScreen(ref: Self.ref,
                         store: PersonStore(ref: Self.ref, credits: FakePersonCredits()))
        }
        .environment(session)
        // `BrowseTile` reads this, and in the app the shell provides it above every pushed
        // destination. Without it here the harness traps on a missing Observable.
        .environment(session.makeTileWatchMarks())
    }
}

private struct FakePersonCredits: PersonCreditsProviding {
    func person(tmdbID: Int) async throws -> TMDBPersonDetails {
        func credit(_ id: Int, _ title: String, _ popularity: Double,
                    character: String? = nil, job: String? = nil) -> TMDBPersonCredit {
            TMDBPersonCredit(
                result: TMDBSearchResult(id: id, title: title, name: nil,
                                         releaseDate: "2021-01-01", firstAirDate: nil,
                                         posterPath: "/p.jpg", overview: nil, voteAverage: 7.5),
                kind: .movie, character: character, job: job, popularity: popularity)
        }
        return TMDBPersonDetails(
            id: tmdbID, name: "Denis Villeneuve", profilePath: nil,
            knownForDepartment: "Directing",
            castCredits: [credit(1, "Talk Show", 99, character: "Self"),      // must NOT appear
                          credit(2, "Cameo Role", 20, character: "Man in Bar"),
                          credit(3, "Bit Part", 10, character: "Officer")],
            crewCredits: [credit(4, "Dune: Part Two", 140, job: "Director"),
                          credit(5, "Arrival", 90, job: "Director"),
                          credit(6, "Blade Runner 2049", 80, job: "Director"),
                          credit(7, "Sicario", 70, job: "Director"),
                          credit(8, "Produced Thing", 200, job: "Producer")]) // must NOT appear
    }
}

// MARK: - Grid top fade

/// A pinned header over an already-scrolled grid — the shape every results grid in the app has, and
/// the shape whose top edge used to guillotine a poster in half.
///
/// The tiles are flat white on purpose. The fade is a brightness ramp, and a ramp is measurable on
/// a flat field and guesswork on a poster; the 100pt default was picked by sampling a column here.
/// Booting straight to it also takes the focus engine out of the question — reaching a real
/// scrolled grid means walking the nav rail with synthesized presses that land where they like.
private struct GridTopFadePreview: View {
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 50)]

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    Button("Movies") {}.buttonStyle(SeretPillStyle(selected: true))
                    Button("TV Shows") {}.buttonStyle(SeretPillStyle(selected: false))
                }
                .padding(.top, 30)
                .padding(.horizontal, Theme.Layout.contentMargin)
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 50) {
                            ForEach(0..<40, id: \.self) { i in
                                Color.white
                                    .frame(height: 330)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner,
                                                                style: .continuous))
                                    .id(i)
                            }
                        }
                        .padding(60)
                    }
                    .gridTopFade()
                    // Scrolled on arrival, so a row is genuinely crossing the top edge. Without it
                    // the fade band sits in the grid's padding and shows nothing at all.
                    .onAppear { proxy.scrollTo(20, anchor: .top) }
                }
            }
        }
    }
}

// MARK: - OpenSubtitles pairing

/// The pairing card on its own, so the QR can be verified without a signed-in session.
///
/// This exists because the alternative did not work: reaching Settings in the simulator means
/// walking the focus engine down the nav rail, and synthesized key presses there land where they
/// like — several attempts ended up in the page instead of on the gear. The card needs no session,
/// so booting straight to it removes the navigation from the question entirely. It also exercises
/// the real `LocalPairingServer`, so a blank QR here means the listener or the address lookup
/// genuinely failed rather than the screenshot being mistimed.
private struct OpenSubtitlesPreview: View {
    @State private var model = SettingsModel(
        secretStore: KeychainSecretStore(service: "com.solomons.seret.opensubtitles.preview"))

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView { OpenSubtitlesSection(model: model).padding(.vertical, 60) }
        }
    }
}

// MARK: - Side menu

/// Both menu states over a stand-in page, so the rail/panel geometry and the label reveal can be
/// screenshot-verified without a signed-in session or the focus engine.
private struct SideMenuPreview: View {
    let startExpanded: Bool

    @FocusState private var focus: SideMenuItem?
    @FocusState private var pageFocus: Int?
    @State private var selected: SideMenuItem = .movies

    var body: some View {
        ZStack(alignment: .leading) {
            CanvasBackground()
            fakePage
                .padding(.leading, SideMenu.railWidth)
                .focusSection()
            SideMenuScrim(visible: startExpanded)
            SideMenu(selected: selected, profileName: "Shahar",
                     profileAvatar: "", profileColorTag: "gold",
                     focus: $focus,
                     expanded: startExpanded,
                     onSelect: { if $0.isPage { selected = $0 } },
                     onProfile: {})
        }
        // Content claims initial focus so the menu starts CLOSED. `.defaultFocus` is the only one
        // of the three candidates that actually wins here — `prefersDefaultFocus(in:)` (leaf or
        // container) loses to tvOS's top-leading heuristic, which the menu always satisfies.
        .defaultFocus($pageFocus, 0)
        .onAppear { if startExpanded { focus = .movies } }
    }

    /// Focusable stand-in posters, so initial focus has somewhere real to land.
    private var fakePage: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Trending Now").sectionTitle()
            HStack(spacing: 36) {
                ForEach(0..<6, id: \.self) { i in
                    Button {} label: {
                        RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous)
                            .fill(Theme.Palette.surface2)
                            .frame(width: 220, height: 330)
                    }
                    .buttonStyle(.card)
                    .focused($pageFocus, equals: i)
                }
            }
        }
        .padding(Theme.Layout.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Movie Detail

/// The real `MovieDetailView` on a stub store that reports a linked rating service, so the star row
/// renders (it's hidden without a watch store) alongside the Versions header. Sign-in free, which
/// is what makes the star styling and the focus geometry between them verifiable in the simulator.
/// An episode row for an episode you own THREE copies of.
///
/// Exists because the real account has no episode with duplicate copies, so the owned-copies
/// "Versions" menu — the half of the feature that only appears when there IS a choice — cannot be
/// reached with live data. The fixture also pins the ordering: the sources are handed over
/// worst-first, so a correctly-ranked row shows the right-sized 2160p first and the 40 GB REMUX
/// last.
private struct EpisodeVersionsPreview: View {
    @State private var store: DetailStore = {
        func src(_ id: String, _ res: String, _ source: String, _ gb: Double) -> MediaSource {
            MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "Sherlock", season: 1, episode: 1,
                                              resolution: res, source: source),
                        sizeBytes: Int(gb * 1_000_000_000))
        }
        // Deliberately worst-first on input.
        let ranked = [src("remux", "2160p", "REMUX", 40),
                      src("web", "2160p", "WEB-DL", 5),
                      src("hd", "1080p", "WEB-DL", 2)].bestFirst()
        let ep = Episode(season: 1, number: 1, source: ranked[0],
                         alternates: Array(ranked.dropFirst()))
        let item = MediaItem(id: "s", kind: .show, title: "Sherlock", year: 2010,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])],
                             tmdbID: 19885)
        return DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatchRating())
    }()
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        let rows = store.episodes(forSeason: 1)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Owned copies, best-first — long-press the card for the menu")
                    .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
                // The ranked order, rendered as text so a screenshot proves it without needing the
                // context menu to be driven open.
                ForEach(rows.first?.ownedVersions ?? [], id: \.self) { s in
                    Text("\(s.parsed.resolution ?? "?") · \(s.parsed.source ?? "?") · "
                         + ByteCountFormatter.string(fromByteCount: Int64(s.sizeBytes ?? 0),
                                                     countStyle: .file))
                        .font(.seretTitle3)
                }
                Text("hasAlternateVersions: \(rows.first?.hasAlternateVersions == true ? "YES" : "NO")")
                    .font(.seretTitle3).foregroundStyle(Theme.Palette.gold)
                if let row = rows.first {
                    EpisodeRow(store: store, row: row)
                }
            }
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CanvasBackground())
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
    }
}

private struct MovieDetailPreview: View {
    @State private var store: DetailStore = {
        let s = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                            parsed: ParsedRelease(title: "The Odyssey", year: 2026,
                                                  resolution: "1080p", source: "TELESYNC",
                                                  videoCodec: "x264"))
        let item = MediaItem(id: "m", kind: .movie, title: "The Odyssey", year: 2026,
                             sources: [s], seasons: [], tmdbID: 1_242_011,
                             overview: "Odysseus takes the long way home.")
        return DetailStore(item: item, details: PreviewDetails(), watch: PreviewWatchRating())
    }()
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))

    var body: some View {
        NavigationStack { MovieDetailView(store: store) }
            .environment(session)
            // The similar/franchise rails render `BrowseTile`, which reads this.
            .environment(session.makeTileWatchMarks())
            // `DetailView` normally drives the rich load; rendering `MovieDetailView` directly
            // skips it, and without it there is no cast and no director to look at.
            .task { await store.load() }
    }
}

/// Inert details provider — the harness renders from the cached `MediaItem` alone.
private struct PreviewDetails: MediaDetailsProviding {
    /// Carries cast and a director so the harness can check the two controls that used to be inert
    /// text: the focusable cast rail, and the pressable director pill.
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        TMDBMovieDetails(
            id: tmdbID, title: "The Odyssey", releaseDate: "2026-07-17", overview: nil,
            posterPath: nil, backdropPath: nil, runtime: 168, genres: [], voteAverage: 7.4,
            cast: [TMDBCastMember(id: 1, name: "Matt Damon", character: "Odysseus",
                                  profilePath: nil, order: 0),
                   TMDBCastMember(id: 2, name: "Tom Holland", character: "Telemachus",
                                  profilePath: nil, order: 1),
                   TMDBCastMember(id: 3, name: "Zendaya", character: "Melantho",
                                  profilePath: nil, order: 2),
                   TMDBCastMember(id: 4, name: "Anne Hathaway", character: "Penelope",
                                  profilePath: nil, order: 3)],
            directors: [TMDBPersonRef(id: 525, name: "Christopher Nolan")])
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

/// A watch store that also rates — `DetailStore.canRate` keys off exactly this conformance.
private struct PreviewWatchRating: WatchProgressProviding, WatchRatingProviding {
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
    func deleteProgress(forContentKeys keys: [String]) async throws {}
    func rating(forContentKey key: String) async -> Int? { nil }
    func setRating(_ value: Int?, forContentKey key: String) async {}
}

// MARK: - Scrub bar

/// Boots straight to `ScrubBar` in each of its states so its layout can be screenshot-verified.
private struct ScrubBarPreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 90) {
                labelled("At rest — 3pt hairline, play-dot handle") { m in }
                labelled("Buffering — inline spinner") { m in m.driveBuffering() }
                labelled("Paused — pause affordance at rest") { m in m.drivePaused() }
                labelled("Scrubbing — slab, thick track, play-mark handle, floating time") { m in
                    m.driveScrubbing()
                }
            }
            .padding(.horizontal, 90)
        }
    }

    private func labelled(_ title: String,
                          drive: @escaping (PreviewDriver) -> Void) -> some View {
        PreviewBarRow(title: title, drive: drive)
    }
}

/// One driven bar plus its caption.
private struct PreviewBarRow: View {
    let title: String
    let drive: (PreviewDriver) -> Void
    @State private var driver = PreviewDriver()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
            ScrubBar(model: driver.model, buffering: driver.buffering)
        }
        .task { await driver.prime(); drive(driver) }
    }
}

/// Builds a `PlayerModel` on a stub engine and drives it into a target state for the harness.
@MainActor
@Observable
final class PreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel
    private(set) var buffering = false

    init() {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in }, subtitles: nil)
    }

    /// Bring the model to a live, rendered, playing state at ~41 minutes of a 2h9m film.
    func prime() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.emit(.time(.init(position: 2481, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(50))
    }

    func driveBuffering() { buffering = true }

    func drivePaused() {
        engine.emit(.state(.paused))
    }

    func driveScrubbing() {
        model.beginScrub()
        model.updateScrub(by: 1600)   // glide the target well ahead of the playhead
    }
}

// MARK: - Input probe

/// Mounts a bare `PlayerInputSurface` over black with the probe HUD on top — no sign-in, no stream,
/// no library. That matters: it makes the remote-input question answerable on a signed-out device
/// or a fresh simulator, and it isolates the surface from every other thing that could swallow
/// input. Launch with `-uiPreview inputprobe -inputHUD`.
private struct InputProbePreview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerInputSurface(
                isActive: true,
                onTouchDown: {}, onTouchUp: {},
                onScrubBegan: {}, onScrubMoved: { _ in },
                onScrubEnded: {}, onScrubCancelled: {},
                onSkip: { _ in }, onSelect: {}, onPlayPause: {}, onUp: {}, onDown: {},
                onScanBegan: { _ in }, onScanEnded: {}
            )
            .ignoresSafeArea()
            InputProbeHUD()
        }
    }
}

// MARK: - Subtitle panel + browser

/// The playback settings panel with muxed tracks grouped apart from downloaded ones.
private struct SettingsPanelPreview: View {
    @State private var driver = SubtitlePreviewDriver()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SettingsPanel(model: driver.model, onSearchSubtitles: {}, onClose: {})
        }
        .task { await driver.primeWithTracks() }
    }
}

/// The full subtitle browser with ranked, badged Hebrew results (an exact hash match sorts first).
///
/// `failing: true` is the state the Apple TV was actually in: results listed, and a pick that
/// cannot be honoured. It exists because the browser used to close itself on failure, so the one
/// screen a viewer sees when the download is refused had never been looked at.
private struct SubtitleBrowserPreview: View {
    private let failing: Bool
    @State private var driver: SubtitlePreviewDriver

    init(failing: Bool = false) {
        self.failing = failing
        _driver = State(initialValue: SubtitlePreviewDriver(failing: failing))
    }

    var body: some View {
        SubtitleBrowser(model: driver.model, onClose: {})
            .task {
                await driver.primeAndSearch()
                if failing, let first = driver.model.subtitleSearchResults.first {
                    await driver.model.useSubtitle(first)
                }
            }
    }
}

/// Drives a `PlayerModel` wired to a canned subtitle provider for the panel/browser harnesses.
@MainActor
@Observable
final class SubtitlePreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel

    init(failing: Bool = false) {
        let source = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "rd://x",
                                 parsed: ParsedRelease(title: "Dune Part Two", year: 2024,
                                                       resolution: "2160p", source: "WEB-DL",
                                                       videoCodec: "H265", releaseGroup: "FLUX"))
        let item = MediaItem(id: "m", kind: .movie, title: "Dune: Part Two", year: 2024,
                             sources: [source], seasons: [], tmdbID: 693134)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: "Dune: Part Two", contentKey: "m")
        model = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _ in },
                            subtitles: PreviewSubtitleProvider(failDownload: failing))
    }

    /// Play, then run a Hebrew search so the browser shows ranked rows.
    func primeAndSearch() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(30))
        await model.searchSubtitles(language: "he")
    }

    /// Play, then ask for Hebrew exactly as the viewer does, so the panel shows both groups AND
    /// the whole download → attach → select path that the picker's state depends on.
    ///
    /// The embedded Hebrew is a `bdpg` bitmap on purpose: that is the shape of the release the
    /// report came from, and it is the track the language preference used to take the selection
    /// back to the instant the download landed.
    func primeWithTracks() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English SDH", language: "en", codec: "subt"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "Français", language: "fr", codec: "subt"),
            MediaTrack(id: "spu/2", kind: .subtitle, name: "עברית", language: "he", codec: "bdpg"),
        ]
        engine.emit(.tracksChanged)
        try? await Task.sleep(for: .milliseconds(30))
        await model.requestSubtitle(language: "he")
        try? await Task.sleep(for: .milliseconds(30))
    }
}

/// A subtitle provider that returns a fixed, ranking-friendly Hebrew set for the harness — one exact
/// file-hash match (perfect), one same-resolution BluRay (uncertain source), one poor CAM rip.
struct PreviewSubtitleProvider: SubtitleProvider {
    /// Refuse the download the way an unconfigured OpenSubtitles account does.
    var failDownload = false
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        [
            SubtitleResult(fileID: 1, language: "he",
                           release: "Dune.Part.Two.2024.2160p.WEB-DL.H265-FLUX",
                           downloadCount: 240, fps: 23.976, moviehashMatch: true, uploader: "syncer"),
            SubtitleResult(fileID: 2, language: "he",
                           release: "Dune.Part.Two.2024.1080p.BluRay.x264-SPARKS",
                           downloadCount: 91_500, fps: 25.0, hearingImpaired: true, uploader: "subber"),
            SubtitleResult(fileID: 3, language: "he",
                           release: "Dune2.CAM.HEBSUB", downloadCount: 4_200, uploader: "anon"),
        ]
    }
    func download(_ result: SubtitleResult) async throws -> URL {
        if failDownload { throw SubtitleError.notAuthenticated }
        return URL(fileURLWithPath: "/tmp/he.srt")
    }
}

// MARK: - Stub engine

/// A no-op engine that just relays emitted events — enough to drive the read-only overlay state.
@MainActor
final class PreviewEngine: VideoPlayerEngine {
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }
    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(url: URL, headers: [String: String], audioLanguage: String?,
              audioTrackID: String?) {}
    func play() {}
    func pause() {}
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// Surface a slave the way VLCKit does — and only the way VLCKit does.
    ///
    /// It used to do nothing, and the panel harness hand-placed a track called "Hebrew" tagged
    /// `language: "he"` instead. VLCKit gives a slave NEITHER: it arrives named "Track 3" with no
    /// language at all, which is precisely why the picker printed "Track 3" for the Hebrew the
    /// viewer had just asked for, and why the language preference could not see it and took the
    /// selection back. A flattering fixture is a harness that cannot show you the bug.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }   // libvlc keys a slave by URL
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
    private var attachedSubtitleURLs: [URL] = []
}
#endif
