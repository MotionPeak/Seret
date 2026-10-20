import DebridCore
import DebridUI
import SwiftUI

/// What Home's hero features: the title you were last watching — or, with nothing under way, the
/// newest arrival in the library.
enum HomeHeroSubject: Equatable {
    case resume(HomeItem)
    case added(MediaItem)

    var item: MediaItem {
        switch self {
        case .resume(let entry): entry.item
        case .added(let item): item
        }
    }
}

/// The hero's actions, supplied by Home (which owns the router and the removal flow).
struct HomeHeroActions {
    /// Resume (or play the up-next episode) — straight into the player.
    var resume: (HomeItem) -> Void
    /// The title's page.
    var open: (MediaItem) -> Void
    /// A play request from the ⋯ menu ("Play from Beginning").
    var play: (PlaybackRequest) -> Void
    /// Ask to remove an owned title (the newest-arrival hero's ⋯ menu).
    var remove: (MediaItem) -> Void
}

/// Home's featured title, both layouts:
///
/// - **compact** (iPhone, g1) — full-bleed backdrop under the status bar and the glass header,
///   fading into the canvas; the logo (else the name), "Continue · 1h 12m left · 1979 · ★ 8.1",
///   then the white Resume pill and glass + / ⋯ circles, all centred.
/// - **regular** (iPad, m5) — the backdrop runs the page's width (under the floating sidebar too);
///   on the left over it: logo, metadata, a three-line synopsis and the same buttons.
///
/// The art (logo, textless backdrop, rating, runtime) comes from `TitleArtStore`, the cache the
/// Apple TV's header uses. Tapping the art opens the title's page; the pill resumes directly.
struct HomeHero: View {
    let subject: HomeHeroSubject
    let home: HomeStore
    let art: TitleArtStore?
    let session: AppSession
    let regular: Bool
    /// The hero's own height — where the rails start.
    let height: CGFloat
    /// iPad, outside the shell only (no `HomeBackdropModel`): how tall the art runs.
    var artHeight: CGFloat = 0
    var leadingMargin: CGFloat = 0
    let actions: HomeHeroActions

    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    /// iPad: the shell draws the art full-width BEHIND the floating sidebar (m5); the hero only
    /// says which. Optional — a non-optional `@Observable` environment read traps when absent.
    @Environment(HomeBackdropModel.self) private var shellBackdrop: HomeBackdropModel?
    /// The art load has answered (with or without art) — the poster stands in for a missing
    /// backdrop only then, so a backdrop on its way is not preceded by the poster.
    @State private var artSettledFor: String?

    private var item: MediaItem { subject.item }
    private var titleArt: TitleArt? {
        guard let id = item.tmdbID else { return nil }
        return art?.art(for: item.kind, tmdbID: id)
    }

    var body: some View {
        Group {
            if regular { regularLayout } else { compactLayout }
        }
        .task(id: item.id) {
            guard let art, let id = item.tmdbID else { artSettledFor = item.id; return }
            _ = await art.load(item.kind, tmdbID: id)
            artSettledFor = item.id
        }
        .onChange(of: regular ? backdropPath : nil, initial: true) { _, path in
            if regular { shellBackdrop?.path = path }
        }
        .onDisappear { if regular { shellBackdrop?.path = nil } }
    }

    /// The art itself opens the title's page — a button to VoiceOver, named for where it goes.
    private func openArea(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture { actions.open(item) }
            .accessibilityElement()
            .accessibilityLabel("Open \(item.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.open(item) }
    }

    private var settling: Bool { artSettledFor != item.id && titleArt == nil }

    /// Path of the art behind the hero: the textless backdrop, else the item's own backdrop, else —
    /// once the art has answered without one — the poster.
    var backdropPath: String? {
        titleArt?.backdropPath ?? item.backdropPath ?? (settling ? nil : item.posterPath)
    }

    // MARK: Compact

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            HomeHeroBackdrop(path: backdropPath)
                .frame(height: height)
            openArea(height: height)
            compactContent.padding(.bottom, 2)
        }
        .frame(height: height)
    }

    private var compactContent: some View {
        VStack(spacing: 14) {
            TitleLogo(title: item.title, logoPath: titleArt?.logoPath, settling: settling,
                      maxWidth: 300, maxHeight: 100, alignment: .bottom)
            metaLine(compact: true)
                .frame(maxWidth: .infinity)
            buttons
        }
        .padding(.horizontal, Theme.Space.xl)
    }

    // MARK: Regular

    private var regularLayout: some View {
        ZStack(alignment: .topLeading) {
            // In the shell the art is drawn behind the sidebar (`HomeBackdropLayer`); only outside
            // it (a preview) does the hero draw its own, running on behind the first rails.
            if shellBackdrop == nil {
                HomeHeroBackdrop(path: backdropPath, leadingShade: true)
                    .frame(height: artHeight)
                    .allowsHitTesting(false)
            }
            // Only the hero's own area opens the page — not the art behind the rails.
            openArea(height: height)
            regularContent
                .padding(.leading, leadingMargin)
                .padding(.trailing, Theme.Space.xxxl)
                // Air between the buttons and the first rail, as in m5.
                .padding(.bottom, 24)
                .frame(height: height, alignment: .bottomLeading)
        }
        .frame(height: height, alignment: .top)
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleLogo(title: item.title, logoPath: titleArt?.logoPath, settling: settling,
                      maxWidth: 420, maxHeight: 110, alignment: .bottomLeading,
                      font: .system(size: 48, weight: .heavy))
            metaLine(compact: false)
            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.82))
                    .lineLimit(3)
                    .frame(maxWidth: 560, alignment: .leading)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            buttons.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    @ViewBuilder private func metaLine(compact: Bool) -> some View {
        let parts = Self.metaParts(subject: subject, art: titleArt, compact: compact)
        HStack(spacing: compact ? 10 : 12) {
            ForEach(parts, id: \.self) { part in
                if part.hasPrefix("★") {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: compact ? 12 : 13))
                        Text(part.dropFirst())
                    }
                } else {
                    Text(part)
                }
            }
        }
        .font(.system(size: compact ? 15 : 17, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.88))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .shadow(color: .black.opacity(0.5), radius: 6)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            primary
            GlassGroup(spacing: 8) {
                HStack(spacing: 14) {
                    watchlistCircle
                    Menu {
                        menuItems
                    } label: {
                        GlassCircleLabel(systemImage: "ellipsis", size: 46)
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("More")
                }
            }
        }
    }

    @ViewBuilder private var primary: some View {
        switch subject {
        case .resume(let entry):
            Button { actions.resume(entry) } label: {
                Label(entry.isUpNext || entry.resumeAt == nil ? "Play" : "Resume", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        case .added(let item):
            Button { actions.open(item) } label: {
                Label("More Info", systemImage: "info.circle")
            }
            .buttonStyle(PrimaryPillButtonStyle())
        }
    }

    /// Films only: Letterboxd has no watchlist a show can go on.
    @ViewBuilder private var watchlistCircle: some View {
        if let film = WatchlistFilm(item: item), let watchlist {
            let on = watchlist.contains(tmdbID: film.tmdbID)
            GlassCircleButton(systemImage: on ? "checkmark" : "plus",
                              label: on ? "Remove from Watchlist" : "Add to Watchlist", size: 46) {
                Task { await watchlist.toggle(film: film) }
            }
            .disabled(watchlist.isInFlight(tmdbID: film.tmdbID))
        }
    }

    @ViewBuilder private var menuItems: some View {
        switch subject {
        case .resume(let entry):
            ContinueWatchingActions(entry: entry, home: home, session: session,
                                    openTitle: { actions.open(entry.item) },
                                    play: actions.play)
        case .added(let item):
            Button(item.kind == .show ? "Go to Show" : "Go to Movie", systemImage: "info.circle") {
                actions.open(item)
            }
            LibraryTitleActions(item: item, session: session, onRemove: actions.remove)
        }
    }

    // MARK: Text

    /// The metadata row. Compact (iPhone): "Continue · 1h 12m left", year, ★ 8.1. Regular (iPad):
    /// year, runtime (or seasons), ★ 8.1, then "1h 12m left" / the episode.
    static func metaParts(subject: HomeHeroSubject, art: TitleArt?, compact: Bool) -> [String] {
        let item = subject.item
        var lead: String?
        var left: String?
        if case .resume(let entry) = subject {
            // The runtime is what the saved position says it is (`resumeAt` is `fraction` of the
            // whole) when TMDB has none — always so for an episode.
            var runtime = item.kind == .movie ? art?.runtimeMinutes : nil
            if runtime == nil, let at = entry.resumeAt, at > 0, entry.fraction > 0 {
                runtime = Int((at / entry.fraction / 60).rounded())
            }
            let remaining = PreviewSubject(home: entry, runtimeMinutes: runtime).remainingMinutes
            left = remaining.map { "\(Self.duration($0)) left" }
            let episode = entry.episode.map { "S\($0.season) · E\($0.number)" }
            if compact {
                let head = entry.isUpNext ? "Up Next" : (left == nil && episode == nil ? "Continue Watching" : "Continue")
                lead = ([head, episode, entry.isUpNext ? nil : left].compactMap { $0 }).joined(separator: " · ")
            } else {
                lead = [entry.isUpNext ? "Up Next" : nil, episode, entry.isUpNext ? nil : left]
                    .compactMap { $0 }.joined(separator: " · ")
            }
        } else if compact {
            lead = "Recently Added"
        }
        let year = item.year.map(String.init)
        let rating = art?.voteAverage.flatMap { $0 > 0 ? String(format: "★%.1f", $0) : nil }
        if compact {
            return [lead, year, rating].compactMap { $0 }.filter { !$0.isEmpty }
        }
        let length: String? = {
            if item.kind == .movie { return art?.runtimeMinutes.map(Self.duration) }
            return art?.seasonCount.map { $0 == 1 ? "1 Season" : "\($0) Seasons" }
        }()
        return [year, length, rating, lead].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// "1h 12m", "45m", "2h".
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// The hero's art: the backdrop, cropped to fill, with the fades that let the logo and buttons read
/// over it and let it run into the canvas. `leadingShade` darkens the left for the iPad's
/// left-aligned preview text.
struct HomeHeroBackdrop: View {
    let path: String?
    var leadingShade = false
    /// Where the page's own content starts (iPad: past the sidebar). The leading shade starts
    /// there, so the art under and around the floating panel keeps its colour, as in m5.
    var shadeInset: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay {
                if let url = TMDBClient.imageURL(path: path, size: "w1280") {
                    RemoteImage(url: url) { Theme.Palette.surface1.opacity(0.4) }
                } else {
                    Theme.Palette.surface1.opacity(0.4)
                }
            }
            .clipped()
            .overlay {
                LinearGradient(stops: [
                    .init(color: Theme.Palette.shadeInk.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .clear, location: 0.42),
                    .init(color: Theme.Palette.canvas.opacity(0.72), location: 0.74),
                    .init(color: Theme.Palette.canvas, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                if leadingShade {
                    LinearGradient(stops: [.init(color: Theme.Palette.canvas.opacity(0.62), location: 0),
                                           .init(color: Theme.Palette.canvas.opacity(0.2), location: 0.5),
                                           .init(color: .clear, location: 0.85)],
                                   startPoint: .leading, endPoint: .trailing)
                        .padding(.leading, shadeInset)
                }
            }
            .animation(Theme.Motion.fade, value: path)
            .accessibilityHidden(true)
    }
}

/// iPad Home's art, which lives in the SHELL rather than on the page: the page is laid out beside
/// the floating sidebar, and nothing inside its NavigationStack can draw past that edge — so the
/// art the mockup runs under and around the panel has to come from behind it. Home's hero says
/// which picture (`path`), Home's scroll view how far it has moved (`offset`), and whether a page
/// pushed over Home should hide it (`hidden`).
@MainActor
@Observable
final class HomeBackdropModel {
    var path: String?
    var offset: CGFloat = 0
    var hidden = false
}

/// The shell's layer for `HomeBackdropModel`: full width from the screen's leading edge, the
/// leading shade starting where the page does, scrolling up with Home's content.
struct HomeBackdropLayer: View {
    let model: HomeBackdropModel
    let pageInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            HomeHeroBackdrop(path: model.path, leadingShade: true, shadeInset: pageInset)
                .frame(width: geo.size.width, height: geo.size.height * 0.92)
                .offset(y: -max(0, model.offset))
        }
        .ignoresSafeArea()
        .opacity(model.path == nil || model.hidden ? 0 : 1)
        .animation(Theme.Motion.fade, value: model.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
