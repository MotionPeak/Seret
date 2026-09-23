#if DEBUG
import DebridCore
import DebridUI
import Foundation

/// Canned data every `-uiPreview` screen builds on: real TMDB poster/backdrop paths, fetched once
/// against the live API and hard-coded here so a screenshot shows real artwork with no network
/// call and no key at preview time. Reused by Tasks 4, 5 and 7.
enum Fixture {
    static func source(id: String, resolution: String = "2160p", videoCodec: String = "HEVC",
                       audioCodec: String = "DTS-HD", sizeBytes: Int = 8_000_000_000) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://real-debrid.invalid/\(id)",
                   parsed: ParsedRelease(title: id, resolution: resolution, source: "BluRay",
                                         videoCodec: videoCodec, audioCodec: audioCodec),
                   sizeBytes: sizeBytes)
    }

    private static func film(_ tmdbID: Int, _ title: String, _ year: Int,
                             _ poster: String, _ backdrop: String) -> MediaItem {
        MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie, title: title, year: year,
                 sources: [source(id: "t\(tmdbID)")], seasons: [], tmdbID: tmdbID,
                 posterPath: poster, backdropPath: backdrop, overview: "A film about \(title).")
    }

    /// ~12 films — includes a long title ("The Lord of the Rings: The Fellowship of the Ring") to
    /// prove a card truncates rather than widening.
    static let films: [MediaItem] = [
        film(693134, "Dune: Part Two", 2024,
             "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", "/eZ239CUp1d6OryZEBPnO2n87gMG.jpg"),
        film(120, "The Lord of the Rings: The Fellowship of the Ring", 2001,
             "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg", "/oiwc338EoBgS4sEI2ixAny4KQKg.jpg"),
        film(238, "The Godfather", 1972,
             "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", "/tSPT36ZKlP2WVHJLM4cQPLSzv3b.jpg"),
        film(27205, "Inception", 2010,
             "/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg"),
        film(157336, "Interstellar", 2014,
             "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg", "/8sNiAPPYU14PUepFNeSNGUTiHW.jpg"),
        film(155, "The Dark Knight", 2008,
             "/qJ2tW6WMUDux911r6m7haRef0WH.jpg", "/9FE5eD92WfVCiivM9Pq9GVSrlWk.jpg"),
        film(496243, "Parasite", 2019,
             "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "/hiKmpZMGZsrkA3cdce8a7Dpos1j.jpg"),
        film(129, "Spirited Away", 2001,
             "/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg", "/6oaL4DP75yABrd5EbC4H2zq5ghc.jpg"),
        film(603, "The Matrix", 1999,
             "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", "/lrtSb1skJayPydZk0OSMAKjBOVe.jpg"),
        film(680, "Pulp Fiction", 1994,
             "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", "/suaEOtk1N1sgg2MTM7oZd2cfVp3.jpg"),
        film(313369, "La La Land", 2016,
             "/uDO8zWDhfWwoFdKS4fzkUJt0Rf0.jpg", "/nlPCdZlHtRNcF6C9hzUH4ebmV1w.jpg"),
        film(872585, "Oppenheimer", 2023,
             "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", "/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg"),
    ]

    private static func episode(_ season: Int, _ number: Int, _ torrentID: String) -> Episode {
        Episode(season: season, number: number, source: source(id: torrentID))
    }

    /// "The" fixture show: a special, a fully-owned season, and a season only partly owned — what
    /// Task 5's season pills / episode grid need to prove Specials-last and "not downloaded".
    static let show: MediaItem = MediaItem(
        id: "show:tmdb:1396", kind: .show, title: "Breaking Bad", year: 2008,
        sources: [], seasons: [
            Season(number: 0, episodes: [episode(0, 1, "bb-s0e1")]),
            Season(number: 1, episodes: (1...6).map { episode(1, $0, "bb-s1e\($0)") }),
            Season(number: 2, episodes: (1...3).map { episode(2, $0, "bb-s2e\($0)") }),
        ],
        tmdbID: 1396, posterPath: "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg",
        backdropPath: "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
        overview: "A high school chemistry teacher turns to manufacturing after a cancer diagnosis.")

    private static func simpleShow(_ tmdbID: Int, _ title: String, _ year: Int,
                                   _ poster: String, _ backdrop: String) -> MediaItem {
        MediaItem(id: "show:tmdb:\(tmdbID)", kind: .show, title: title, year: year, sources: [],
                 seasons: [Season(number: 1, episodes: (1...6).map { episode(1, $0, "\(tmdbID)-s1e\($0)") })],
                 tmdbID: tmdbID, posterPath: poster, backdropPath: backdrop)
    }

    static let shows: [MediaItem] = [
        show,
        simpleShow(19885, "Sherlock", 2010,
                  "/7WTsnHkbA0FaG6R9twfFde0I9hl.jpg", "/8rvLEmdI4gLrMO1rLqbNdnNcPFE.jpg"),
        simpleShow(1399, "Game of Thrones", 2011,
                  "/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg", "/zZqpAXxVSBtxV9qPBcscfXBcL2w.jpg"),
    ]

    /// Canned watch state: one finished film, one mid-watch film, and the fixture show's first
    /// three S1 episodes (two finished, one mid-watch) — what the poster/episode badges render.
    static let watch: [String: WatchState] = {
        var map: [String: WatchState] = [:]
        func set(_ key: String, source: MediaSource, position: Double, duration: Double, finished: Bool) {
            map[key] = WatchState(contentKey: key, sourceKey: WatchKey.source(source),
                                  positionSeconds: position, durationSeconds: duration,
                                  finished: finished, updatedAt: .now)
        }
        let godfather = films[2]
        set(WatchKey.content(forMovie: godfather), source: godfather.sources[0],
           position: 8150, duration: 8160, finished: true)

        let dune = films[0]
        set(WatchKey.content(forMovie: dune), source: dune.sources[0],
           position: 3753, duration: 8160, finished: false)

        let s1 = show.seasons.first { $0.number == 1 }!.episodes
        for ep in s1.prefix(2) {
            set(WatchKey.content(forShow: show, episode: ep), source: ep.source,
               position: 2570, duration: 2580, finished: true)
        }
        if let e3 = s1.first(where: { $0.number == 3 }) {
            set(WatchKey.content(forShow: show, episode: e3), source: e3.source,
               position: 1210, duration: 2580, finished: false)
        }
        return map
    }()
}

/// A fake `LibraryProviding` for the harness: no Real-Debrid, no TMDB — canned items, or a
/// scripted empty/hang/failure — so every `LibraryStore.State` can be screenshot-verified.
struct PreviewLibrary: LibraryProviding {
    enum Mode {
        case items([MediaItem]), loadingForever, failing, empty
    }
    let mode: Mode

    func loadCached() -> [MediaItem]? {
        switch mode {
        case .items(let items): return items
        case .empty: return []
        case .loadingForever, .failing: return nil
        }
    }

    func refresh() async throws -> [MediaItem] {
        switch mode {
        case .items(let items): return items
        case .empty: return []
        case .loadingForever:
            try await Task.sleep(for: .seconds(3600))
            return []
        case .failing:
            throw URLError(.notConnectedToInternet)
        }
    }

    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

/// A fake `WatchProgressProviding` over an in-memory map. Records into it, so marking watched in
/// the harness actually changes what the next read sees.
actor PreviewWatch: WatchProgressProviding {
    private var states: [String: WatchState]

    init(_ seed: [String: WatchState] = [:]) { states = seed }

    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { states[key] }

    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        keys.reduce(into: [:]) { $0[$1] = states[$1] }
    }

    func record(contentKey: String, sourceKey: String, positionSeconds: Double, durationSeconds: Double,
               finished: Bool, profileID: String) async throws {
        states[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                        positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                                        finished: finished, updatedAt: .now)
    }

    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { [] }

    func deleteProgress(forContentKeys keys: [String]) async throws {
        for key in keys { states.removeValue(forKey: key) }
    }
}

/// A fake `MediaDetailsProviding` for the title-page harness: canned TMDB details for the fixture
/// film and show — real still paths for Breaking Bad S1/S2 (fetched once, like Task 3's posters),
/// no network. Season 2 lists 8 episodes against 3 owned (`Fixture.show`), so `titleshows2` shows
/// exactly "3 owned, 5 not downloaded".
struct PreviewDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        let title = Fixture.films.first { $0.tmdbID == tmdbID }?.title ?? "Film"
        return TMDBMovieDetails(id: tmdbID, title: title, releaseDate: nil, overview: nil,
                                posterPath: nil, backdropPath: nil, runtime: 167,
                                genres: [TMDBGenre(id: 1, name: "Science Fiction"), TMDBGenre(id: 2, name: "Adventure")],
                                voteAverage: nil)
    }

    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: Fixture.show.title, firstAirDate: nil, overview: nil,
                      posterPath: nil, backdropPath: nil, numberOfSeasons: 2,
                      genres: [TMDBGenre(id: 1, name: "Crime"), TMDBGenre(id: 2, name: "Drama")], voteAverage: nil)
    }

    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        switch season {
        case 1: return Self.season1
        case 2: return Self.season2
        default: return []
        }
    }

    private static func episode(_ n: Int, _ name: String, _ still: String, _ runtime: Int) -> TMDBEpisodeDetails {
        TMDBEpisodeDetails(episodeNumber: n, name: name, overview: nil, stillPath: still, runtime: runtime, airDate: nil)
    }

    /// Breaking Bad S1 — all 6 owned by `Fixture.show`.
    static let season1: [TMDBEpisodeDetails] = [
        episode(1, "Pilot", "/88Z0fMP8a88EpQWMCs1593G0ngu.jpg", 59),
        episode(2, "Cat's in the Bag...", "/AbMoecO0ZZio0LcgeLxlzdyGs6X.jpg", 49),
        episode(3, "...And the Bag's in the River", "/2kBeBlxGqBOdWlKwzAxiwkfU5on.jpg", 49),
        episode(4, "Cancer Man", "/2UbRgW6apE4XPzhHPA726wUFyaR.jpg", 49),
        episode(5, "Gray Matter", "/82G3wZgEvZLKcte6yoZJahUWBtx.jpg", 49),
        episode(6, "Crazy Handful of Nothin'", "/rCCLuycNPL30W3BtuB8HafxEMYz.jpg", 49),
    ]

    /// Breaking Bad S2 — only the first 3 are owned by `Fixture.show`; 4–8 stay "not downloaded".
    static let season2: [TMDBEpisodeDetails] = [
        episode(1, "Seven Thirty-Seven", "/6Uo1z56uKnX60JXvYYFWACHR31u.jpg", 48),
        episode(2, "Grilled", "/th3SNe0gNgRguv8VveLd4f2JcaH.jpg", 48),
        episode(3, "Bit by a Dead Bee", "/abgJTOWYPdZGxAWhsg6lmtM8qcU.jpg", 47),
        episode(4, "Down", "/gMXeL0qcQZi5Tfd4UhnkRJeI9oa.jpg", 48),
        episode(5, "Breakage", "/bPQxF63jhfT5eNYjhzuGEO7oMQg.jpg", 48),
        episode(6, "Peekaboo", "/tfCuh20gNHGGF6A1te3NmiqML6D.jpg", 48),
        episode(7, "Negro y Azul", "/1IOnhCCeru1BZUPeppu7tMmtxvL.jpg", 48),
        episode(8, "Better Call Saul", "/KmFdF23FtbPwwz3FJF2T885r2Z.jpg", 48),
    ]
}

/// A no-op engine that relays emitted events — enough to drive `PlayerModel` end to end with no
/// VLCKit. Port of `Apps/SeretMobile/Playback/PlayerUIPreview.swift`'s `MobilePreviewEngine`, plus
/// `play()`/`pause()` emitting `.state(.playing)`/`.state(.paused)` so the harness transport (Space,
/// the play/pause button) actually moves the model.
@MainActor
final class PreviewEngine: VideoPlayerEngine {
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private var attachedSubtitleURLs: [URL] = []

    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(url: URL, headers: [String: String], audioLanguage: String?, audioTrackID: String?) {}
    func play() { emit(.state(.playing)) }
    func pause() { emit(.state(.paused)) }
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// Surface a slave the way VLCKit does — named "Track N", with NO language, never twice for the
    /// same URL.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
}

/// Drives a `PlayerModel` over `PreviewEngine` with no VLCKit and no network, so every player
/// `-uiPreview` case shows real model state (phase, tracks, playhead) rather than hand-placed view
/// fields. `failing` makes the load itself fail, so the failure text shown is the shared model's own
/// ("The Real-Debrid link could not be opened.") rather than a harness-invented string.
@MainActor
@Observable
final class PlayerPreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel

    /// `hangs`: the unrestrict never returns, so `PlayerScreen`'s own `.onAppear { model.start() }`
    /// begins loading but never gets past it — `phase` stays `.preparing` and the cold-open overlay
    /// (title + "Preparing…" + shimmer) stays on screen, which is what "not primed" (`playerloading`)
    /// needs to show. `failing` throws instead, so the failure text shown is the shared model's own.
    init(failing: Bool = false, hangs: Bool = false) {
        let item = Fixture.films[0]
        let source = item.sources[0]
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: item.title, contentKey: item.id)
        let unrestrict: (String) async throws -> URL
        if hangs {
            unrestrict = { _ in try await Task.sleep(for: .seconds(3600)); return URL(string: "https://example.invalid/film.mkv")! }
        } else if failing {
            unrestrict = { _ in throw URLError(.timedOut) }
        } else {
            unrestrict = { _ in URL(string: "https://example.invalid/film.mkv")! }
        }
        model = PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil, loadTimeout: 3600)
    }

    /// `start()`, then the sequence a real play makes: tracks discovered, `.playing`, and a moving
    /// playhead (two ticks — the second is what marks the first rendered frame) — so the HUD is
    /// screenshot-verified against real model state, not hand-placed fields.
    func prime() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.audioTracks = [
            MediaTrack(id: "audio/0", kind: .audio, name: "English 5.1 (E-AC-3)", language: "en", codec: "eac3"),
            MediaTrack(id: "audio/1", kind: .audio, name: "English 2.0 (AAC)", language: "en", codec: "mp4a"),
        ]
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en", codec: "subt"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "English SDH", language: "en", codec: "subt"),
            MediaTrack(id: "spu/2", kind: .subtitle, name: "עברית", language: "he", codec: "subt"),
        ]
        engine.emit(.tracksChanged)
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 3752, duration: 8160)))
        try? await Task.sleep(for: .milliseconds(30))
        engine.emit(.time(.init(position: 3753, duration: 8160)))
        try? await Task.sleep(for: .milliseconds(30))
    }
}
#endif
