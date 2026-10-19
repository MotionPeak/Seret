#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// `-uiPreview plexrails`: a `FocusBrowsePage` on fixture titles with real TMDB art, laid out
/// inside the same leading inset the shell gives a page, so a screenshot measures against the
/// approved mockup's Home frame.
///
/// The fixture covers what the header and tiles must cope with: a film with a logo (Whiplash —
/// the first tile, focused at launch), films and shows without one (the title as text), tiles
/// with progress and chips, a watched tile, and one title with NOTHING — no poster, no backdrop,
/// no synopsis, no TMDB match — and a Hebrew name.
///
/// - `plexrailsnoart` starts focused ON that tile, mid-rail, through the page's `initialFocus`
///   hook (not the tvOS top-leading default), so its header and the canvas fallback show at launch.
/// - `plexrailsinsert` starts in the second rail and, 4 s in, inserts a rail above it — the page
///   must bring the focused rail back to the top. `plexrailsinsertearly` inserts it 300ms after focus
///   first lands, while the initial-focus scroll is still settling.
/// - Every tile carries a context menu and an outside `.plexFocusID`, stacked on `PosterTile`;
///   a long-press menu action is echoed top-right.
///
/// The details fake answers after 300ms, so the page's settle (logo budget, late art) is
/// exercised the way a real TMDB round trip exercises it.
struct PlexRailsPreview: View {
    enum Variant { case standard, noArt, insert, insertEarly }
    var variant = Variant.standard

    @State private var preview = FocusPreviewModel()
    @State private var art = TitleArtStore(details: PlexRailsFixture.Details())
    /// `insert`: a rail that arrives late, ABOVE the focused one.
    @State private var lateRail = false
    @State private var log = ""
    @State private var earlyInsertScheduled = false

    var body: some View {
        FocusBrowsePage(preview: preview, art: art, initialFocus: initialFocus) {
            if lateRail {
                rail("Arrived Late", id: "late", Array(PlexRailsFixture.shows.reversed()))
            }
            rail("Continue Watching", id: "continue", PlexRailsFixture.continueWatching)
            rail("Recently Added Movies", id: "movies", PlexRailsFixture.movies)
            rail("Recently Added Shows", id: "shows", PlexRailsFixture.shows)
        }
        // The shell's content inset, so x positions match the real app.
        .sideMenuContentInset()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        .overlay(alignment: .topTrailing) {
            // What the context menu did, so a screenshot can prove it fired.
            if !log.isEmpty {
                Text(log).font(.seret(22, .semibold)).foregroundStyle(Theme.Palette.onFocus)
                    .padding(12).background(Theme.Palette.focus, in: Capsule()).padding(40)
            }
        }
        .onAppear { preview.showImmediately(initialSubject) }
        .task {
            guard variant == .insert else { return }
            try? await Task.sleep(for: .seconds(4))
            lateRail = true      // a plain store update, as rails arriving from a load are
        }
    }

    private var initialFocus: String {
        switch variant {
        case .standard: tileID("continue", PlexRailsFixture.continueWatching[0])
        // Mid-rail, NOT the tvOS default (top-leading) — proves the page's focus hook.
        case .noArt:    tileID("continue", PlexRailsFixture.hebrew)
        // In the second rail, so a rail inserted above it has to move the page.
        case .insert, .insertEarly: tileID("movies", PlexRailsFixture.movies[0])
        }
    }

    private var initialSubject: PreviewSubject {
        switch variant {
        case .standard: PlexRailsFixture.continueWatching[0].subject
        case .noArt:    PlexRailsFixture.hebrew.subject
        case .insert, .insertEarly: PlexRailsFixture.movies[0].subject
        }
    }

    /// `insertEarly`: 300ms after focus first lands — inside the settle window of the page's
    /// initial-focus scroll, which is exactly when rails streaming in from a load arrive. Timed from
    /// the focus rather than from appear, because a rail inserted before focus resolves would push
    /// the initial-focus target out of the lazy stack before it ever took focus.
    private func scheduleEarlyInsert() {
        guard variant == .insertEarly, !earlyInsertScheduled else { return }
        earlyInsertScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            lateRail = true
        }
    }

    private func tileID(_ rail: String, _ entry: PlexRailsFixture.Entry) -> String { "\(rail)/\(entry.id)" }

    private func rail(_ title: String, id: String, _ entries: [PlexRailsFixture.Entry]) -> some View {
        PlexRail(title: title, id: id) {
            ForEach(entries) { entry in
                PosterTile(posterPath: entry.subject.posterPath, title: entry.subject.title,
                           progress: entry.progress, chip: entry.chip, watched: entry.watched,
                           onFocus: { preview.focus(entry.subject); scheduleEarlyInsert() }, action: { log = "Played \(entry.subject.title)" })
                    // Stacked on the tile from outside: the page's focus hook and a context menu.
                    .plexFocusID(tileID(id, entry))
                    .contextMenu {
                        Button("Mark Watched", systemImage: "checkmark.circle") {
                            log = "Marked \(entry.subject.title) watched"
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            log = "Removed \(entry.subject.title)"
                        }
                    }
            }
        }
    }
}

enum PlexRailsFixture {
    struct Entry: Identifiable, Equatable {
        var id: String { subject.id }
        let subject: PreviewSubject
        var progress: Double?
        var chip: String?
        var watched = false
    }

    struct Facts: Sendable {
        let vote: Double
        let runtime: Int?
        let seasons: Int?
        let genres: [String]
        let logo: String?
    }

    static func movie(_ tmdbID: Int?, _ title: String, _ year: Int?, poster: String?, backdrop: String?,
                      _ overview: String?, progress: Double? = nil, chip: String? = nil,
                      watched: Bool = false) -> Entry {
        let id = tmdbID.map { "movie:tmdb:\($0)" } ?? "movie:\(title)"
        let item = MediaItem(id: id, kind: .movie, title: title, year: year, sources: [], seasons: [],
                             tmdbID: tmdbID, posterPath: poster, backdropPath: backdrop, overview: overview)
        return Entry(subject: PreviewSubject(item: item), progress: progress, chip: chip, watched: watched)
    }

    static func show(_ tmdbID: Int, _ title: String, _ year: Int, poster: String, backdrop: String,
                     _ overview: String, progress: Double? = nil, chip: String? = nil) -> Entry {
        let item = MediaItem(id: "show:tmdb:\(tmdbID)", kind: .show, title: title, year: year,
                             sources: [], seasons: [], tmdbID: tmdbID, posterPath: poster,
                             backdropPath: backdrop, overview: overview)
        return Entry(subject: PreviewSubject(item: item), progress: progress, chip: chip)
    }

    /// No poster, no backdrop, no synopsis, no TMDB match — and a Hebrew title.
    static let hebrew = movie(nil, "גבעת חלפון אינה עונה", 1976, poster: nil, backdrop: nil, nil,
                              progress: 0.4)

    static let continueWatching: [Entry] = [
        movie(244786, "Whiplash", 2014, poster: "/7fn624j5lj3xTme2SgiLCeuedmO.jpg",
              backdrop: "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg",
              "A young jazz drummer enrols at a cut-throat conservatory, where a ferocious instructor will stop at nothing to push him past his limits.",
              progress: 0.35),
        show(247718, "MobLand", 2025, poster: "/5Xc7WpWsgflfgEMoBlf9TmWhfbH.jpg",
             backdrop: "/h0OC7ouop8YLwbAVfS3UUE2Lw4T.jpg",
             "Two rival crime families collide in London, and the fixer caught between them has to keep both alive.",
             progress: 0.72),
        show(153312, "Tulsa King", 2022, poster: "/rOYLWCdAifpUtPlTf1WHxyaxeMt.jpg",
             backdrop: "/mNHRGO1gFpR2CYZdANe72kcKq7G.jpg",
             "Fresh out of prison, a New York capo is exiled to Oklahoma and starts building an empire from nothing.",
             chip: "Next"),
        hebrew,
        show(203857, "The Diplomat", 2023, poster: "/cUy0ZYme43lop08nOtbQLWL0dX.jpg",
             backdrop: "/hzznrBI07C2chXivlLYvEmQESP7.jpg",
             "A career diplomat lands a high-profile posting in London during an international crisis — and in a marriage under strain.",
             progress: 0.18),
        movie(969681, "Spider-Man: Brand New Day", 2026, poster: "/bjiS5ipwxb9JFy3XRRN4OAilSeX.jpg",
              backdrop: "/r08LxMJCbf1SiJIWeyH9aJmdqwC.jpg",
              "Peter Parker tries to build a life no one remembers him in, until the city needs Spider-Man again.",
              progress: 0.55),
        show(95350, "Lanterns", 2026, poster: "/rb94rKVIzLyfWufIN7WqLvadBDH.jpg",
             backdrop: "/6gqezQJ2mkm4jreWwLyOZy2Vf6i.jpg",
             "Two Green Lanterns investigate a murder in the American heartland that leads somewhere much darker.",
             chip: "New Season"),
        movie(1400940, "Clayface", 2026, poster: "/5jCpQnWPikggmQZoDp1eAi6BI6w.jpg",
              backdrop: "/kVtOcoUJ68chBD2tmERkdWz7lK5.jpg",
              "A disfigured actor discovers he can reshape himself into anyone, and sets out to take back his life.",
              progress: 0.86),
    ]

    static let movies: [Entry] = [
        movie(1288069, "Tenzing", 2026, poster: "/eI0QW02PYqhnmIvLRdn9vrfVVP7.jpg",
              backdrop: "/6GXqVvL20Y0MpyVP30WoI2NPK69.jpg",
              "The story of the Sherpa who stood on the summit of Everest in 1953."),
        movie(1058424, "Hope", 2026, poster: "/6VY1ZKgpsc8CfGsQcCGiYEgHdH0.jpg",
              backdrop: "/qqHFLg90IUSoTmSMpKOOW5RyqN3.jpg",
              "A village police chief investigates a creature attacking his harbour town.", watched: true),
        movie(1561726, "Masterplan", 2026, poster: "/5xmXVd7nCK3tAo34XkO58SxUCip.jpg",
              backdrop: "/dgUDj84BWtW6EZzee8BkgKnjDhh.jpg", "A heist planned to the minute goes wrong at every step."),
        movie(1153576, "Street Fighter", 2026, poster: "/pwUb3gdkSrlyMZWs0MFOQg3N5s7.jpg",
              backdrop: "/5H5YphHsQmkQhrw13Wv1whCZKtN.jpg", "Fighters from around the world meet in one tournament."),
        movie(1302904, "Practical Magic 2", 2026, poster: "/ogwQOLbCfncjvBhFb5l0OmQH8KC.jpg",
              backdrop: "/oIglj0Jy9duG4LnrRUpH8n001Pk.jpg", "The Owens sisters face a curse that has followed the family for generations."),
        movie(1255833, "Whalefall", 2026, poster: "/vjTYUTgh9nO88i6HZ4YPRhiFL05.jpg",
              backdrop: "/shW2jHkQLZVv4Fko2rJDqTGU0gx.jpg", "A diver swallowed by a sperm whale has one hour of air to get out."),
        movie(1236045, "Animals", 2026, poster: "/iISM36voS1E8gX9BM0DVK0kgi3E.jpg",
              backdrop: "/tzoarEu7TsG959upiELyYPm5kO9.jpg", "A family's road trip turns into a fight for survival."),
        movie(1514026, "Buddy", 2026, poster: "/1BdZbNvl1SfrrX8J9X5tQzN6Ivu.jpg",
              backdrop: "/ytoLEl5yDaxB8AtZ52uKWjaQ9ql.jpg", "A children's TV mascot comes to life with plans of his own."),
    ]

    static let shows: [Entry] = [
        show(213562, "Crystal Lake", 2026, poster: "/3ENhExiD2fcjk5FX0AcAXcvLu9N.jpg",
             backdrop: "/wxiBsKFEOOFK8eQStWOykNORlXY.jpg", "The summer camp everyone was warned about opens again."),
        show(213375, "VisionQuest", 2026, poster: "/WGyAyBPncfuu8MZhLY9RtfZPM0.jpg",
             backdrop: "/uoXXbN2PrOxH6UKyP7kYwmGpAAP.jpg", "A synthetic hero searches for what remains of himself."),
        show(288673, "Carrie", 2026, poster: "/6mUMquPQBFJGqTACS3Azkwwrx8d.jpg",
             backdrop: "/9yCJtipMeDe8uAdSJKvw8BnYfRz.jpg", "A bullied teenager discovers a power she cannot control."),
        show(285322, "Below", 2026, poster: "/vgLqqhMUbljp585qPp1EFCyJtcz.jpg",
             backdrop: "/cn0feYcDvVzVjUDoXa1O8sRgzz.jpg", "A crew trapped on the ocean floor runs out of time."),
        show(123542, "LINK CLICK", 2021, poster: "/hCt2bLRGTCjHGqtV5FP3Img6w1h.jpg",
             backdrop: "/w3agwUSMpJ4X9t1jGrDtqqRPjDQ.jpg", "Two friends who can step into photographs take on their clients' pasts."),
        show(30984, "Bleach", 2004, poster: "/2EewmxXe72ogD0EaWM8gqa0ccIw.jpg",
             backdrop: "/o0NsbcIvsllg6CJX0FBFY8wWbsn.jpg", "A teenager gains the powers of a Soul Reaper."),
        show(37854, "One Piece", 1999, poster: "/dB4EDhre2dsC2kxYDavyKWqLQwi.jpg",
             backdrop: "/v38qp4bySLTXYu3MF8r5GD51FN3.jpg", "A rubber-limbed pirate sets sail for the greatest treasure in the world."),
    ]

    /// What the details fake knows, by TMDB id. Whiplash alone has a logo.
    static let facts: [Int: Facts] = [
        244786: Facts(vote: 8.4, runtime: 107, seasons: nil, genres: ["Drama", "Music"],
                      logo: "/kTmh3W4iWQnNUcnYNgxgOVhpzCe.png"),
        969681: Facts(vote: 8.5, runtime: 128, seasons: nil, genres: ["Action", "Adventure"], logo: nil),
        1400940: Facts(vote: 7.9, runtime: 104, seasons: nil, genres: ["Horror"], logo: nil),
        247718: Facts(vote: 8.5, runtime: nil, seasons: 1, genres: ["Crime", "Drama"], logo: nil),
        153312: Facts(vote: 8.3, runtime: nil, seasons: 3, genres: ["Crime", "Drama"], logo: nil),
        203857: Facts(vote: 7.6, runtime: nil, seasons: 3, genres: ["Drama"], logo: nil),
        95350: Facts(vote: 8.2, runtime: nil, seasons: 1, genres: ["Sci-Fi & Fantasy"], logo: nil),
    ]

    /// Answers after 300ms, like a TMDB round trip. Titles it has no facts for get a bare answer.
    struct Details: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            try await Task.sleep(for: .milliseconds(300))
            let f = facts[tmdbID]
            return TMDBMovieDetails(
                id: tmdbID, title: "", releaseDate: nil, overview: nil, posterPath: nil,
                backdropPath: nil, runtime: f?.runtime ?? 112,
                genres: (f?.genres ?? ["Drama"]).enumerated().map { TMDBGenre(id: $0.offset, name: $0.element) },
                voteAverage: f?.vote ?? 7.0,
                images: TMDBImageSet(backdrops: [], logos: f?.logo.map {
                    [TMDBImageRef(filePath: $0, languageCode: "en", voteAverage: 5, width: 800)]
                } ?? []))
        }

        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
            try await Task.sleep(for: .milliseconds(300))
            let f = facts[tmdbID]
            return TMDBTVDetails(
                id: tmdbID, name: "", firstAirDate: nil, overview: nil, posterPath: nil,
                backdropPath: nil, numberOfSeasons: f?.seasons ?? 2,
                genres: (f?.genres ?? ["Drama"]).enumerated().map { TMDBGenre(id: $0.offset, name: $0.element) },
                voteAverage: f?.vote ?? 7.4)
        }

        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }
}
#endif
