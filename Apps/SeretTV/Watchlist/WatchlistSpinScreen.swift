import DebridCore
import DebridUI
import SwiftUI

/// "Surprise Me" — the Mac's Cover Flow reel, on the TV: spins through the watchlist and lands on
/// one film to watch.
///
/// The winner is chosen by `WatchlistRandomizer` BEFORE anything moves, and the reel is built to
/// end on it. The animation is therefore pure presentation: it cannot change the answer, and a
/// reel interrupted half-way still names the film the picker chose.
///
/// Its posters and the winner's backdrop load first, then the reel runs — every card turning in 3D
/// as it passes through the middle, with a mirror under it — and settles the winner in the gold
/// frame. The winner's own backdrop then fades in behind everything, drifting, with its logo art
/// over it. Reduce Motion shows the winner straight away, flat. The geometry is
/// `SurpriseReelLayout`, shared with the Mac so the two reels stay one design.
struct WatchlistSpinScreen: View {
    let spin: WatchlistRandomizer.Spin
    /// Where the winner's backdrop and logo come from. Nil, or a failed fetch, leaves the plain
    /// background and the text title — the reel never waits on it.
    let details: MediaDetailsProviding?
    let onWatch: (WatchlistEntry) -> Void
    let onSpinAgain: () -> Void
    let onClose: () -> Void
    /// Harness only: the winner's backdrop/logo paths to use instead of fetching its details.
    var artOverride: (backdropPath: String?, logoPath: String?)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the reel is, in cards: 0 = the first card centred, `winnerIndex` = landed. Animating
    /// this ONE value is what makes the deceleration real: SwiftUI interpolates it along the timing
    /// curve and every card's pose is derived from it, so the whole reel slows together.
    @State private var position: Double = 0
    @State private var landed = false
    /// False while the posters are still loading — a reel that starts before its art arrives runs
    /// blank cards through the frame.
    @State private var ready = false
    @State private var backdropURL: URL?
    @State private var logoPath: String?
    @FocusState private var focus: Field?

    private enum Field { case watch, again }

    static let spinDuration = 3.4

    var body: some View {
        GeometryReader { geo in
            let card = SurpriseReelLayout.cardSize(windowWidth: geo.size.width, windowHeight: geo.size.height)
            ZStack {
                background
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Surprise Me")
                        .eyebrow()
                        .foregroundStyle(Theme.Palette.gold)
                        .padding(.bottom, 44)
                    CoverFlowReel(position: position, entries: spin.reel, winnerIndex: spin.winnerIndex,
                                  landed: landed, cardSize: card, flat: reduceMotion)
                        .frame(width: geo.size.width, height: card.height * SurpriseReelLayout.reelHeightFactor)
                        .opacity(ready ? 1 : 0.35)
                        .animation(Theme.Anim.pageFade, value: ready)
                    landedDetail
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        // Keyed on the spin itself, so "Spin Again" restarts the reel even when it lands on the
        // same film — and leaving cancels the run instead of letting it finish off screen.
        .task(id: spin.id) { await run() }
        // MENU backs out without picking anything.
        .onExitCommand(perform: onClose)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            // Opaque: the watchlist grid must not show through the reel.
            Theme.Palette.canvas
            RadialGradient(colors: [Theme.Palette.gold.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 900)
            if landed, let backdropURL {
                DriftingBackdrop(url: backdropURL, drifts: !reduceMotion)
                    .opacity(0.55)
                    .overlay {
                        // Keep the middle calm for the reel, and the edges dark.
                        RadialGradient(colors: [Theme.Palette.canvas.opacity(0.35), Theme.Palette.canvas.opacity(0.92)],
                                       center: .center, startRadius: 160, endRadius: 1150)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.9)))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Winner copy

    /// Fixed height, conditional content.
    ///
    /// NOT `.opacity(landed ? 1 : 0)`: a fully transparent view cannot take focus on tvOS, so
    /// "Watch It" would be assigned focus mid-fade and the assignment silently dropped — the
    /// result appeared with the remote pointing at nothing. Reserving the space with a frame keeps
    /// the reel from jumping while letting the buttons genuinely not exist until there is
    /// something to press.
    private var landedDetail: some View {
        ZStack {
            if landed {
                VStack(spacing: 0) {
                    WinnerTitle(logoPath: logoPath, title: WatchlistName.stripYear(from: spin.winner.name))
                        .frame(height: 110)
                    if let year = spin.winner.year {
                        Text("\(String(year)) · from your watchlist")
                            .calloutText()
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.top, 12)
                    }
                    HStack(spacing: 24) {
                        Button("Watch It", systemImage: "play.fill") { onWatch(spin.winner) }
                            .buttonStyle(SeretActionButtonStyle())
                            .focused($focus, equals: .watch)
                        Button("Spin Again", systemImage: "dice.fill", action: onSpinAgain)
                            .buttonStyle(SeretPillStyle(selected: false))
                            .focused($focus, equals: .again)
                    }
                    .padding(.top, 28)
                }
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
        }
        .frame(height: 280, alignment: .top)
        .animation(Theme.Anim.heroSpring, value: landed)
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
        } else {
            // Fast at first, then a long settle — the shape of a wheel losing momentum.
            withAnimation(.timingCurve(0.12, 0.72, 0.18, 1, duration: Self.spinDuration)) { position = target }
            // The reel is `.timingCurve`-driven, so "it has stopped" is a matter of the clock
            // rather than something the animation reports back. Matching the duration is what
            // keeps the result from appearing over cards that are still moving.
            try? await Task.sleep(for: .seconds(Self.spinDuration))
            guard !Task.isCancelled else { return }
        }
        await art
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Anim.heroSpring) { landed = true }
        // One turn after `landed`, so the buttons have actually been inserted — focus cannot be
        // assigned to a view that does not exist yet.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        focus = .watch
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
    ///
    /// Every write is behind a cancellation check: "Spin Again" cancels this run and the next one
    /// resets the state at once, without waiting for this fetch to wind down — so a late answer
    /// for the OLD winner would otherwise put its backdrop and logo under the new one.
    private func loadWinnerArt() async {
        let backdropPath: String?, logo: String?
        if let artOverride {
            (backdropPath, logo) = artOverride
        } else {
            guard let tmdbID = spin.winner.tmdbID, let details,
                  let film = try? await details.movieDetails(tmdbID: tmdbID) else { return }
            (backdropPath, logo) = (film.preferredBackdropPath, film.logoPath)
        }
        // Into the cache before they are shown, so they fade in whole rather than popping in late.
        if let url = TMDBClient.imageURL(path: logo, size: "w500") {
            _ = await ImageMemoryCache.load(url)
        }
        guard !Task.isCancelled else { return }
        logoPath = logo
        if let url = TMDBClient.imageURL(path: backdropPath, size: "w1280") {
            _ = await ImageMemoryCache.load(url)
            guard !Task.isCancelled else { return }
            backdropURL = url
        }
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

    // `nonisolated`: SwiftUI drives `animatableData` off the main actor while interpolating, and
    // under Swift 6 a plain conformance on a View would cross isolation. The value is a Double on
    // a value type, so there is nothing to race on.
    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(SurpriseReelLayout.visibleIndices(position: position, count: entries.count), id: \.self) { index in
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

    private static let corner: CGFloat = 16
    private var url: URL? { TMDBClient.imageURL(path: entry.posterPath, size: "w500") }

    var body: some View {
        VStack(spacing: 8) {
            poster
                .overlay {
                    if isWinner {
                        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                            .strokeBorder(Theme.Palette.goldGradient, lineWidth: 4)
                            .goldGlow(26, opacity: 0.7)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 28, y: 16)
            poster
                .scaleEffect(x: 1, y: -1)
                .frame(width: size.width, height: size.height * 0.32, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
        }
        .brightness(dimmed ? -0.35 : 0)
        .animation(Theme.Anim.heroSpring, value: isWinner)
        .animation(Theme.Anim.pageFade, value: dimmed)
    }

    /// A plain surface while the art is missing — not the spinning poster placeholder, which would
    /// spin through the frame (and upside down in the mirror) on a card that is only flying past.
    private var poster: some View {
        RemoteImage(url: url) { _ in Theme.Palette.surface1 }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
    }
}

/// The winner's title art — TMDB's own logo when there is one, the plain text title otherwise.
/// The text IS the placeholder, so loading, a missing logo and a decode failure all read the same
/// correct way rather than as a blank gap.
private struct WinnerTitle: View {
    let logoPath: String?
    let title: String

    var body: some View {
        RemoteImage(url: TMDBClient.imageURL(path: logoPath, size: "w500"), contentMode: .fit) { _ in
            Text(title)
                .screenTitle()
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // Bottom-aligned, so a short text title (or a wide, flat logo) sits on the year line
        // rather than floating in the middle of the box a tall logo needs.
        .frame(maxWidth: 560, maxHeight: 110, alignment: .bottom)
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
    }
}

/// The winner's backdrop, slowly drifting (scale + a small pan over 24 s, back and forth) — the
/// Mac's Ken Burns, so the landed screen is alive rather than a still.
private struct DriftingBackdrop: View {
    let url: URL
    let drifts: Bool

    var body: some View {
        GeometryReader { geo in
            Group {
                if drifts {
                    image.phaseAnimator([false, true]) { content, drifted in
                        content
                            .scaleEffect(drifted ? 1.09 : 1)
                            .offset(x: drifted ? -0.014 * geo.size.width : 0,
                                    y: drifted ? -0.012 * geo.size.height : 0)
                    } animation: { _ in .easeInOut(duration: 24) }
                } else {
                    image
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var image: some View {
        RemoteImage(url: url) { _ in Color.clear }
    }
}
