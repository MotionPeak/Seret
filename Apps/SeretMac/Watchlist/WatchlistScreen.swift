import DebridCore
import DebridUI
import SwiftUI

/// The Watchlist section (spec §6): the Letterboxd watchlist, synced on open when stale and on
/// *Sync*; a status line; a grid (owned ✓, unmatched "No TMDB match" tiles); Remove from Watchlist
/// (confirmed, relayed through the Seret server); and Surprise Me. Without a Letterboxd username
/// it says where to set one.
struct WatchlistRoot: View {
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(WatchlistModel.self) private var injected: WatchlistModel?
    @State private var model: WatchlistModel?

    var body: some View {
        Group {
            if let model = injected ?? model {
                WatchlistScreen(model: model)
            } else {
                unavailable
            }
        }
        .task {
            guard injected == nil else { return }
            if model == nil { model = session?.makeWatchlistModel() }
            await model?.syncIfStale()
        }
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.gold)
            Text("Your Letterboxd watchlist lives here")
                .font(Theme.Typo.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Set your Letterboxd username in Settings.")
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
            SettingsLink { Text("Open Settings…") }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WatchlistScreen: View {
    let model: WatchlistModel
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    @State private var pendingRemoval: WatchlistEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Watchlist")
                    .font(Theme.Typo.titleXL())
                    .foregroundStyle(Theme.Palette.textPrimary)
                statusRow
                content
            }
            .padding(.leading, pageLeadingInset)
            .padding(.trailing, 28)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(removalTitle, isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                if let entry = pendingRemoval { Task { await model.remove(entry) } }
                pendingRemoval = nil
            }
        } message: {
            Text("It's removed on Letterboxd too.")
        }
    }

    private var removalTitle: String {
        "Remove \u{201C}\(pendingRemoval.map { WatchlistName.stripYear(from: $0.name) } ?? "")\u{201D} from your watchlist?"
    }

    @ViewBuilder private var statusRow: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .idle:
                if model.canSpin {
                    Button {
                        if let spin = model.spin() {
                            let model = model
                            shell?.surprise = .init(spin: spin, respin: { model.spin() })
                        }
                    } label: {
                        Label("Surprise Me", systemImage: "dice.fill")
                    }
                    .buttonStyle(GoldButtonStyle())
                }
                Button("Sync") { Task { await model.syncNow() } }
                    .buttonStyle(GlassButtonStyle())
                if !model.entries.isEmpty {
                    Text("\(model.entries.count) film\(model.entries.count == 1 ? "" : "s")")
                        .font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                if let message = model.relayMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.destructive)
                        .lineLimit(1)
                }
            case .syncing(let done, let total):
                ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                    .frame(width: 120)
                    .tint(Theme.Palette.gold)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
            case .failed(let message):
                Button("Try Again") { Task { await model.syncNow() } }
                    .buttonStyle(GlassButtonStyle())
                Text(message)
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.destructive)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty {
            if case .syncing = model.phase {
                PosterGrid(items: [MediaItem](), isLoading: true) { (_: MediaItem) in EmptyView() }
            } else {
                Text("Nothing on your watchlist yet.")
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.top, 20)
            }
        } else {
            PosterGrid(items: model.entries,
                       prefetchURL: { TMDBClient.imageURL(path: $0.posterPath, size: "w342") }) { entry in
                WatchlistTile(entry: entry, owned: model.isOwned(entry),
                              onOpen: { item in shell?.open(.title(item)) },
                              onRemove: { pendingRemoval = entry })
            }
        }
    }
}

/// One watchlist film: its poster (✓ when it's in your library) or, when TMDB couldn't match it,
/// a named placeholder. Click opens the title page; right-click offers Open and Remove.
private struct WatchlistTile: View {
    let entry: WatchlistEntry
    let owned: Bool
    let onOpen: (MediaItem) -> Void
    let onRemove: () -> Void
    /// Where the pointer is over the poster (0…1 each way) — drives the same tilt, glare and gold
    /// rim as every other poster; nil when it isn't over it.
    @State private var pointer: UnitPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: MediaItem? { MediaItem.watchlistMovie(entry) }
    private var title: String { WatchlistName.stripYear(from: entry.name) }

    var body: some View {
        Group {
            if let item {
                Button { onOpen(item) } label: {
                    PosterCard(title: title, caption: entry.year.map(String.init) ?? "",
                               posterURL: TMDBClient.imageURL(path: entry.posterPath, size: "w342"),
                               badge: owned ? .watched : .none, highlighted: pointer != nil,
                               pointer: reduceMotion ? nil : pointer)
                }
                .buttonStyle(.plain)
                .onContinuousHover(coordinateSpace: .local) { phase in
                    if case .active(let p) = phase {
                        pointer = UnitPoint(x: p.x / PosterCard.posterSize.width,
                                            y: p.y / PosterCard.posterSize.height)
                    } else {
                        pointer = nil
                    }
                }
            } else {
                unmatched
            }
        }
        .contextMenu {
            if let item { Button("Open") { onOpen(item) } }
            Button("Remove from Watchlist…", role: .destructive, action: onRemove)
        }
        .help(owned ? "\(title) — in your library" : title)
    }

    private var unmatched: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.surface1)
                .frame(width: PosterCard.posterSize.width, height: PosterCard.posterSize.height)
                .overlay {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(10)
                }
            Text("No TMDB match")
                .font(Theme.Typo.caption())
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(width: PosterCard.posterSize.width, alignment: .leading)
    }
}

/// Surprise Me (spec §6, mockup 3), as a Cover Flow: the winner is chosen first, its posters and
/// backdrop load, then the reel runs for 3.4 s — every card turning in 3D as it passes through the
/// middle, with a mirror under it — and settles the winner in the gold frame. The winner's own
/// backdrop then fades in behind everything, drifting, with its logo art over it.
/// *Watch It* (Return) opens it, *Spin Again* re-rolls, *Close* (Esc) leaves.
/// Reduce Motion shows the winner straight away, flat.
struct SurpriseReel: View {
    let spin: WatchlistRandomizer.Spin
    let onWatch: (WatchlistEntry) -> Void
    let onSpinAgain: () -> Void
    let onClose: () -> Void
    /// Harness only: the winner's backdrop/logo paths to use instead of fetching its details.
    var artOverride: (backdropPath: String?, logoPath: String?)? = nil

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the reel is, in cards: 0 = the first card centred, `winnerIndex` = landed.
    @State private var position: Double = 0
    @State private var landed = false
    /// False while the posters are still loading — a reel that starts before its art arrives runs
    /// blank cards through the frame.
    @State private var ready = false
    @State private var backdropURL: URL?
    @State private var logoPath: String?

    static let spinDuration = 3.4

    var body: some View {
        GeometryReader { geo in
            let card = SurpriseReelLayout.cardSize(windowWidth: geo.size.width, windowHeight: geo.size.height)
            ZStack {
                background
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("SURPRISE ME")
                        .font(Theme.Typo.label()).tracking(2.4)
                        .foregroundStyle(Theme.Palette.gold)
                        .padding(.bottom, 44)
                    CoverFlowReel(position: position, entries: spin.reel, winnerIndex: spin.winnerIndex,
                                  landed: landed, cardSize: card, flat: reduceMotion)
                        .frame(width: geo.size.width, height: card.height * 1.36)
                        .opacity(ready ? 1 : 0.35)
                        .animation(Theme.Motion.fade, value: ready)
                    winnerCopy
                        .frame(height: 150, alignment: .top)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .task(id: spin.id) { await run() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            // Opaque: the page and sidebar must not show through the reel.
            Theme.Palette.canvas
            RadialGradient(colors: [Theme.Palette.gold.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 700)
            if landed, let backdropURL {
                HeroBackdrop(url: backdropURL, drifts: true)
                    .opacity(0.55)
                    .overlay {
                        // Keep the middle calm for the reel, and the edges dark.
                        RadialGradient(colors: [Theme.Palette.canvas.opacity(0.35), Theme.Palette.canvas.opacity(0.92)],
                                       center: .center, startRadius: 120, endRadius: 900)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.9)))
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { if landed { onClose() } }
    }

    // MARK: - Winner copy

    private var winnerCopy: some View {
        VStack(spacing: 14) {
            Group {
                if let logoPath {
                    TitleLogo(path: logoPath, title: WatchlistName.stripYear(from: spin.winner.name))
                        .frame(maxWidth: 380, maxHeight: 64)
                } else {
                    Text(WatchlistName.stripYear(from: spin.winner.name))
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 3)
                }
            }
            .frame(height: 64)
            if let year = spin.winner.year {
                Text("\(String(year)) · from your watchlist")
                    .font(Theme.Typo.caption())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            HStack(spacing: 12) {
                Button { onWatch(spin.winner) } label: { Label("Watch It", systemImage: "play.fill") }
                    .buttonStyle(GoldButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button(action: onSpinAgain) { Label("Spin Again", systemImage: "dice.fill") }
                    .buttonStyle(GlassButtonStyle())
                Button("Close", action: onClose)
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .opacity(landed ? 1 : 0)
        .offset(y: landed || reduceMotion ? 0 : 12)
        .animation(Theme.Motion.pop, value: landed)
        .allowsHitTesting(landed)
    }

    // MARK: - Running it

    private func run() async {
        landed = false
        ready = false
        position = 0
        backdropURL = nil
        logoPath = nil
        async let art: Void = loadWinnerArt()
        await preloadPosters()
        guard !Task.isCancelled else { return }
        ready = true
        let target = Double(spin.winnerIndex)
        if reduceMotion {
            position = target
            await art
            landed = true
            return
        }
        withAnimation(.timingCurve(0.12, 0.72, 0.18, 1, duration: Self.spinDuration)) { position = target }
        try? await Task.sleep(for: .seconds(Self.spinDuration))
        guard !Task.isCancelled else { return }
        await art
        withAnimation(Theme.Motion.pop) { landed = true }
    }

    /// Every poster the reel will show, into the image cache first — at most 2.5 s, after which it
    /// spins with whatever has arrived rather than keep the viewer waiting.
    private func preloadPosters() async {
        let urls = Set(spin.reel.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w500") })
        let loader = Task {
            await withTaskGroup(of: Void.self) { group in
                for url in urls { group.addTask { _ = await ImageMemoryCache.load(url) } }
            }
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(2.5))
            loader.cancel()
        }
        await loader.value
        deadline.cancel()
    }

    /// The winner's backdrop and logo — fetched while the reel spins, so both are ready to fade in
    /// the moment it lands. A failure just leaves the plain background and the text title.
    private func loadWinnerArt() async {
        if let artOverride {
            logoPath = artOverride.logoPath
            if let url = TMDBClient.imageURL(path: artOverride.backdropPath, size: "w1280") {
                _ = await ImageMemoryCache.load(url)
                backdropURL = url
            }
            return
        }
        guard let tmdbID = spin.winner.tmdbID, let details = session?.detailsProvider,
              let film = try? await details.movieDetails(tmdbID: tmdbID) else { return }
        logoPath = film.logoPath
        if let url = TMDBClient.imageURL(path: film.preferredBackdropPath, size: "w1280") {
            _ = await ImageMemoryCache.load(url)
            backdropURL = url
        }
    }
}

/// The reel's sizes: big, but always fitting — cards scale with the window so the whole visible
/// flow (the centre card and three either side) stays inside it.
enum SurpriseReelLayout {
    static func cardSize(windowWidth: CGFloat, windowHeight: CGFloat) -> CGSize {
        let width = min(280, max(170, windowWidth * 0.19), max(170, windowHeight * 0.3))
        return CGSize(width: width, height: width * 1.5)
    }

    /// Horizontal centre of a card `r` places from the middle (fractional while moving): the
    /// centre gap is wide, the side cards stack tighter, as in Cover Flow.
    static func x(r: Double, cardWidth: CGFloat) -> CGFloat {
        let centreGap = cardWidth * 0.82, sideStep = cardWidth * 0.36
        let a = abs(r)
        let distance = a <= 1 ? a * centreGap : centreGap + (a - 1) * sideStep
        return CGFloat(r < 0 ? -distance : distance)
    }

    /// The turn toward the middle: ±50° beyond the first neighbour, 0 at the centre.
    static func angle(r: Double) -> Double { max(-1, min(1, r)) * -50 }

    static func scale(r: Double) -> CGFloat {
        let a = abs(r)
        return CGFloat(1 - 0.14 * min(a, 1) - 0.03 * max(0, a - 1))
    }

    /// Fully visible to three places out, gone by four.
    static func opacity(r: Double) -> Double {
        let a = abs(r)
        return a <= 3 ? 1 : max(0, 1 - (a - 3))
    }
}

/// The flowing strip itself. `Animatable` on `position`, so while it spins SwiftUI re-lays it out on
/// every frame from the in-between position — each card turns through the middle and away again,
/// rather than tweening straight from its start pose to its end pose.
private struct CoverFlowReel: View, Animatable {
    var position: Double
    let entries: [WatchlistEntry]
    let winnerIndex: Int
    let landed: Bool
    let cardSize: CGSize
    let flat: Bool

    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    private var visible: [Int] {
        guard !entries.isEmpty else { return [] }
        let centre = Int(position.rounded())
        return Array(max(0, centre - 5)...min(entries.count - 1, centre + 5))
    }

    var body: some View {
        ZStack {
            ForEach(visible, id: \.self) { index in
                let r = Double(index) - position
                let isWinner = landed && index == winnerIndex
                ReelCard(entry: entries[index], size: cardSize, isWinner: isWinner, dimmed: landed && !isWinner)
                    .scaleEffect(SurpriseReelLayout.scale(r: r) * (isWinner ? 1.06 : 1))
                    .rotation3DEffect(.degrees(flat ? 0 : SurpriseReelLayout.angle(r: r)),
                                      axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .offset(x: SurpriseReelLayout.x(r: r, cardWidth: cardSize.width))
                    .opacity(SurpriseReelLayout.opacity(r: r))
                    .zIndex(-abs(r))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One poster in the reel, with its mirror fading out beneath it.
private struct ReelCard: View {
    let entry: WatchlistEntry
    let size: CGSize
    let isWinner: Bool
    let dimmed: Bool

    private var url: URL? { TMDBClient.imageURL(path: entry.posterPath, size: "w500") }

    var body: some View {
        VStack(spacing: 6) {
            poster
                .overlay {
                    if isWinner {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.Palette.goldGradient, lineWidth: 3)
                            .shadow(color: Theme.Palette.gold.opacity(0.7), radius: 22)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
            poster
                .scaleEffect(x: 1, y: -1)
                .frame(width: size.width, height: size.height * 0.32, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .brightness(dimmed ? -0.35 : 0)
        .animation(Theme.Motion.pop, value: isWinner)
        .animation(Theme.Motion.fade, value: dimmed)
    }

    private var poster: some View {
        RemoteImage(url: url)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
