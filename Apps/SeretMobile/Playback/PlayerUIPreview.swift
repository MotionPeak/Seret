#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only visual harness for the player's subtitle surfaces, mirroring SeretTV's
/// `PlayerUIPreview`.
///
/// Reaching the real sheet means signing in to Real-Debrid and playing something, and RD throttles
/// its device-code endpoint hard enough that re-authenticating a simulator is not a thing to do
/// casually — so this boots straight to the sheet with a `PlayerModel` driven through the actual
/// download → attach → select path on a stub engine.
///
/// Launch with `-uiPreview <target>`:
///   - `playbacksheet`   — the playback sheet after Hebrew has been asked for and attached
///   - `subtitlebrowser` — the ranked search browser
///   - `autosync` / `autosyncdone` / `autosyncfailed` — the subtitle-sync bar over the picture
///   - `episodeswap` — the real player screen two seconds into S1E1, then S1E2 picked; the stub
///     engine never answers for E2, so the screen stays on the swap — what it shows there is the
///     point. `episodeswapopening`: the same, but libvlc never reports buffering for E2 either, so
///     the swap stays in its `.preparing` stage (the "Preparing…" overlay)
///   - `showdetail` — the real show page for a show you own with S1E2 part-watched: Resume + Start,
///     the season list, the episode rows (long-press one for its menu)
///   - `letterboxdrating` / `letterboxdrerating` — the post-credits rating prompt, unrated and
///     already rated 7. Prints what the tap produced, so a screenshot answers it
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview playbacksheet
///
/// Not compiled into release builds.
struct PlayerUIPreview: View {
    let target: String
    @State private var driver = MobileSubtitlePreviewDriver()

    var body: some View {
        Group {
            switch target {
            case "letterboxdrating":   MobileRatingBarPreview(existing: nil)
            case "letterboxdrerating": MobileRatingBarPreview(existing: 7)
            case "autosync":        MobileAutoSyncPreview(mood: .measuring)
            case "autosyncdone":    MobileAutoSyncPreview(mood: .synced)
            case "autosyncfailed":  MobileAutoSyncPreview(mood: .failed)
            case "episodeswap":     MobileEpisodeSwapPreview()
            case "episodeswapopening": MobileEpisodeSwapPreview(reportsBuffering: false)
            case "showdetail":      MobileShowDetailPreview()
            case "subtitlebrowser":
                // Tinted here because in the app the browser is pushed INSIDE the settings sheet,
                // which sets the gold tint — an untinted harness screenshot would show system blue
                // and misrepresent it.
                NavigationStack { MobileSubtitleBrowser(model: driver.model) }
                    .tint(Theme.Palette.gold)
                    .task { await driver.primeAndSearch() }
            default:
                PlayerSettingsSheet(model: driver.model)
                    .task { await driver.primeWithTracks() }
            }
        }
        // RootView sets this app-wide; the harness bypasses RootView, so without it these
        // screenshots render light and misrepresent how the sheet actually looks.
        .preferredColorScheme(.dark)
    }
}

/// Drives a `PlayerModel` wired to a canned subtitle provider and a stub engine.
@MainActor
@Observable
final class MobileSubtitlePreviewDriver {
    let engine = MobilePreviewEngine()
    let model: PlayerModel

    init() {
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
                            recordProgress: { _, _, _, _, _ in },
                            subtitles: MobilePreviewSubtitleProvider())
    }

    /// Play, then ask for Hebrew exactly as a tap on the chip does — so the sheet shows the real
    /// outcome of the whole path, not a hand-placed track that flatters it.
    ///
    /// The embedded Hebrew is a `bdpg` bitmap on purpose: that is the shape of the release the
    /// report came from, and the track the language preference used to take the selection back to.
    func primeWithTracks() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        engine.audioTracks = [
            MediaTrack(id: "audio/0", kind: .audio, name: "English", language: "en", codec: "a52 "),
            MediaTrack(id: "audio/1", kind: .audio, name: "Français", language: "fr", codec: "a52 "),
        ]
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

    func primeAndSearch() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.time(.init(position: 2480, duration: 7784)))
        try? await Task.sleep(for: .milliseconds(30))
        await model.searchSubtitles(language: "he")
    }
}

/// A fixed, ranking-friendly Hebrew set: one exact file-hash match (perfect), one same-resolution
/// BluRay at the wrong rate, one poor CAM rip.
struct MobilePreviewSubtitleProvider: SubtitleProvider {
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
        URL(fileURLWithPath: "/tmp/he-\(result.fileID).srt")
    }
}

/// A no-op engine that relays emitted events — enough to drive the read-only overlay state, plus
/// the one behaviour the subtitle path genuinely depends on (below).
@MainActor
final class MobilePreviewEngine: VideoPlayerEngine {
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

    /// Surface a slave the way VLCKit does — named "Track 3", with NO language, and never twice for
    /// the same URL. Both of those are load-bearing: the missing language is why the preference
    /// could not see a downloaded subtitle, and the URL keying is why asking twice used to hang.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
    private var attachedSubtitleURLs: [URL] = []
}

/// The auto-sync bar over a stand-in film frame, in whichever of its three states.
///
/// A sync runs for minutes with the film still playing, so this bar is the only thing telling the
/// viewer it is alive — which makes its legibility over a bright picture, and whether its longest
/// message fits a narrow phone, the whole question. Only a screenshot settles either.
/// The real `ShowDetail` over fixed details and watch state — no session, no network.
private struct MobileShowDetailPreview: View {
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var store: DetailStore = {
        let source = { (id: String) in
            MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "The Sopranos", resolution: "1080p"))
        }
        let seasons = (1...2).map { s in
            Season(number: s, episodes: (1...3).map { n in
                Episode(season: s, number: n, source: source("s\(s)e\(n)"))
            })
        }
        let show = MediaItem(id: "show:tmdb:1398", kind: .show, title: "The Sopranos", year: 1999,
                             sources: [], seasons: seasons, tmdbID: 1398,
                             overview: "New Jersey mob boss Tony Soprano deals with personal and professional issues.")
        return DetailStore(item: show, details: Details(), watch: Watch(), profileID: "preview")
    }()

    var body: some View {
        ShowDetail(store: store, onPlay: { request in
            print("[preview] play \(request.label) fromStart=\(request.fromStart) resumeAt=\(String(describing: request.resumeAt))")
        })
        .environment(session)
        .environment(session.makeTileWatchMarks())
        .task { await store.load() }
    }

    private struct Details: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            TMDBTVDetails(id: tmdbID, name: "The Sopranos", firstAirDate: "1999-01-10",
                          overview: "New Jersey mob boss Tony Soprano deals with personal and professional issues.",
                          posterPath: nil, backdropPath: nil, numberOfSeasons: 2, genres: [], voteAverage: 8.6)
        }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
            (1...3).map { n in
                TMDBEpisodeDetails(episodeNumber: n, name: ["Pilot", "46 Long", "Denial, Anger, Acceptance"][n - 1],
                                   overview: "Tony's world shifts as the family business and the family collide.",
                                   stillPath: nil, runtime: 55, airDate: "1999-01-10")
            }
        }
    }

    /// S1E1 finished, S1E2 part-way — so Play reads "Resume S1·E2" and Start sits beside it.
    private struct Watch: WatchProgressProviding {
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            switch key {
            case "show:tmdb:1398:s1e1":
                return WatchState(contentKey: key, sourceKey: "s1e1#1", positionSeconds: 3200,
                                  durationSeconds: 3300, finished: true, updatedAt: Date().addingTimeInterval(-600))
            case "show:tmdb:1398:s1e2":
                return WatchState(contentKey: key, sourceKey: "s1e2#1", positionSeconds: 1250,
                                  durationSeconds: 3000, finished: false, updatedAt: Date())
            default:
                return nil
            }
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }
}

/// The real `PlayerView` over a model driven by the stub engine; the VLC engine is there only for
/// its (black) video surface.
private struct MobileEpisodeSwapPreview: View {
    /// Whether libvlc reports buffering for E2 (moving the swap from `.preparing` to `.buffering`).
    var reportsBuffering = true
    @State private var engine = MobilePreviewEngine()
    @State private var surface = VLCKitVideoPlayerEngine()
    @State private var model: PlayerModel?

    var body: some View {
        Group {
            if let model {
                PlayerView(model: model, engine: surface, backdropURL: nil, onExit: {})
            } else {
                Color.black
            }
        }
        .task { await run() }
    }

    private func run() async {
        let source = { (id: String) in
            MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                        parsed: ParsedRelease(title: "The Bear", resolution: "1080p"))
        }
        let e1 = Episode(season: 1, number: 1, source: source("e1"))
        let e2 = Episode(season: 1, number: 2, source: source("e2"))
        let item = MediaItem(id: "show:tmdb:136315", kind: .show, title: "The Bear", year: 2022,
                             sources: [], seasons: [Season(number: 1, episodes: [e1, e2])], tmdbID: 136315)
        let request = PlaybackRequest(item: item, source: e1.source, resumeAt: nil,
                                      label: "The Bear — S1·E1",
                                      contentKey: WatchKey.content(forShow: item, episode: e1), episode: e1)
        let m = PlayerModel(request: request, engine: engine,
                            unrestrict: { _ in URL(string: "https://cdn/x.mkv")! },
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil)
        model = m
        m.start()
        try? await Task.sleep(for: .milliseconds(300))
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 600, duration: 1320)))
        engine.emit(.time(.init(position: 601, duration: 1320)))
        try? await Task.sleep(for: .seconds(2))
        m.play(e2)                                   // the strip's next episode
        try? await Task.sleep(for: .milliseconds(300))
        if reportsBuffering { engine.emit(.state(.buffering)) }   // what libvlc reports opening E2
    }
}

private struct MobileAutoSyncPreview: View {
    let mood: PlayerModel.AutoSyncBanner.Mood

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.orange, .white, .teal, .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            AutoSyncBar(banner: banner).padding(.top, 14)
        }
    }

    private var banner: PlayerModel.AutoSyncBanner {
        switch mood {
        case .measuring:
            .init(text: "Syncing subtitles  \u{00B7}  about 3 min left", mood: .measuring,
                  fraction: 0.38)
        case .synced:
            .init(text: "Subtitles synced  \u{00B7}  shifted +1.4s", mood: .synced, fraction: nil)
        case .failed:
            .init(text: "Couldn't sync the subtitles \u{2014} nudge the timing by hand",
                  mood: .failed, fraction: nil)
        }
    }
}


/// The post-credits rating prompt over a stand-in for the picture.
///
/// Ten tap targets in a phone-width bar is the thing worth looking at: the glyphs are 15pt and
/// sit two points apart, so whether a thumb can actually land on the one it is aiming at is a
/// question only a screenshot at real size answers.
private struct MobileRatingBarPreview: View {
    let existing: Int?
    @State private var signal = LetterboxdPushSignal()
    @State private var picked = "nothing tapped yet"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("the film, playing")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.28))
                Text(picked)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeretPalette.gold)
            }
        }
        .letterboxdDiaryBar(signal: signal, contentKey: "movie:tmdb:73") { state in
            switch state {
            case .logged: LetterboxdLoggedBar().padding(.top, 14)
            case .askingRating(_, let current):
                LetterboxdRatingBar(current: current) { value in
                    picked = value.map { "rated \($0)/10" } ?? "rating cleared"
                } onDismiss: {
                    picked = "dismissed — logged unrated"
                }
                .padding(.top, 14)
            }
        }
        .task { signal.askForRating(tmdbID: 73, current: existing) }
    }
}

#endif
