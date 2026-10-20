import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// "Surprise Me" — the Apple TV's and the Mac's Cover Flow reel, on the phone: it spins through
/// the watchlist and lands on one film to watch. Presented as a sheet, so a swipe down puts it away.
///
/// The winner is chosen by `WatchlistRandomizer` BEFORE anything moves, and the reel is built to
/// end on it: the animation is pure presentation and cannot change the answer. The geometry is
/// `SurpriseReelLayout`, shared with the TV and the Mac so the three reels are one design.
///
/// Posters load first, then the reel runs and settles the winner in a white frame; its backdrop
/// fades in behind, drifting. Tap the winner (or Watch It) for its title page; Spin Again, or a
/// swipe across the reel, spins again. Reduce Motion lands at once, flat.
struct WatchlistSpinScreen: View {
    let details: MediaDetailsProviding?
    /// A fresh spin over the list as it stands now — nil when nothing is left to land on.
    let respin: () -> WatchlistRandomizer.Spin?
    let onWatch: (WatchlistEntry) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The spin on screen. Replaced in place by Spin Again, so the sheet never re-presents.
    @State private var current: WatchlistRandomizer.Spin
    /// Where the reel is, in cards: 0 = the first card centred, `winnerIndex` = landed. Animating
    /// this ONE value makes the deceleration real — every card's pose derives from it.
    @State private var position: Double = 0
    @State private var landed = false
    /// False while posters are still loading — a reel that starts before its art runs blank cards.
    @State private var ready = false
    @State private var backdropURL: URL?
    @State private var logoPath: String?

    static let spinDuration = 3.4

    init(spin: WatchlistRandomizer.Spin, details: MediaDetailsProviding?,
         respin: @escaping () -> WatchlistRandomizer.Spin?,
         onWatch: @escaping (WatchlistEntry) -> Void, onClose: @escaping () -> Void) {
        _current = State(initialValue: spin)
        self.details = details
        self.respin = respin
        self.onWatch = onWatch
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geo in
            let card = SurpriseReelLayout.cardSize(windowWidth: geo.size.width,
                                                   windowHeight: geo.size.height)
            ZStack {
                background
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("SURPRISE ME")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.bottom, Theme.Space.xxl)
                    CoverFlowReel(position: position, entries: current.reel,
                                  winnerIndex: current.winnerIndex, landed: landed,
                                  cardSize: card, flat: reduceMotion)
                        .frame(width: geo.size.width,
                               height: card.height * SurpriseReelLayout.reelHeightFactor)
                        .opacity(ready ? 1 : 0.35)
                        .animation(Theme.Motion.fade, value: ready)
                        .contentShape(Rectangle())
                        // The winner itself opens its page; a swipe across the reel spins again.
                        .onTapGesture { if landed { onWatch(current.winner) } }
                        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                            if landed, abs(value.translation.width) > abs(value.translation.height) {
                                spinAgain()
                            }
                        })
                        .accessibilityElement()
                        .accessibilityLabel(landed ? "Picked \(winnerTitle)" : "Spinning")
                        .accessibilityAddTraits(landed ? .isButton : [])
                        .accessibilityAction { if landed { onWatch(current.winner) } }
                    landedDetail
                        .padding(.top, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.xl)
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .overlay(alignment: .topTrailing) {
                GlassCircleButton(systemImage: "xmark", label: "Close", size: 40, action: onClose)
                    .padding(Theme.Space.lg)
            }
        }
        // Keyed on the spin itself, so Spin Again restarts the reel even on the same film — and
        // leaving cancels the run instead of letting it finish off screen.
        .task(id: current.id) { await run() }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.canvas)
        .presentationSizing(.page)
    }

    private var winnerTitle: String { WatchlistName.stripYear(from: current.winner.name) }

    private func spinAgain() {
        guard let next = respin() else { return }
        current = next
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Theme.Palette.canvas
            if landed, let backdropURL {
                DriftingBackdrop(url: backdropURL, drifts: !reduceMotion)
                    .opacity(0.5)
                    .overlay {
                        // Keep the middle calm for the reel, and the edges dark.
                        RadialGradient(colors: [Theme.Palette.canvas.opacity(0.35),
                                                Theme.Palette.canvas.opacity(0.92)],
                                       center: .center, startRadius: 80, endRadius: 620)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.9)))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Winner copy

    /// Fixed height, conditional content — the reel never jumps when the result appears.
    private var landedDetail: some View {
        ZStack {
            if landed {
                VStack(spacing: 0) {
                    WinnerTitle(logoPath: logoPath, title: winnerTitle)
                        .frame(height: 76)
                    if let year = current.winner.year {
                        Text("\(String(year)) · from your watchlist")
                            .font(Theme.Typo.body())
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .padding(.top, Theme.Space.sm)
                    }
                    HStack(spacing: Theme.Space.md) {
                        PrimaryPill(title: "Watch It", systemImage: "play.fill") { onWatch(current.winner) }
                        GlassPill(title: "Spin Again", systemImage: "dice.fill", action: spinAgain)
                    }
                    .padding(.top, Theme.Space.xl)
                }
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
        }
        .frame(height: 210, alignment: .top)
        .animation(Theme.Motion.hero, value: landed)
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
        let target = Double(current.winnerIndex)
        if reduceMotion {
            position = target
        } else {
            // Fast at first, then a long settle — a wheel losing momentum.
            withAnimation(.timingCurve(0.12, 0.72, 0.18, 1, duration: Self.spinDuration)) { position = target }
            // The reel is curve-driven, so "it has stopped" is the clock's to say.
            try? await Task.sleep(for: .seconds(Self.spinDuration))
            guard !Task.isCancelled else { return }
        }
        await art
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Motion.hero) { landed = true }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Every poster the reel will show, into the image cache first — at most 2.5 s, after which it
    /// spins with whatever has arrived.
    private func preloadPosters() async {
        let urls = Set(current.reel.compactMap { TMDBClient.imageURL(path: $0.posterPath, size: "w500") })
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

    /// The winner's backdrop and logo, fetched while the reel spins. A failure leaves the plain
    /// background and the text title. Every write checks cancellation: Spin Again starts a new run
    /// at once, and a late answer for the OLD winner must not land under the new one.
    private func loadWinnerArt() async {
        guard let tmdbID = current.winner.tmdbID, let details,
              let film = try? await details.movieDetails(tmdbID: tmdbID) else { return }
        let backdropPath = film.preferredBackdropPath ?? film.backdropPath, logo = film.logoPath
        if let url = TMDBClient.imageURL(path: logo, size: "w500") { _ = await ImageMemoryCache.load(url) }
        guard !Task.isCancelled else { return }
        logoPath = logo
        if let url = TMDBClient.imageURL(path: backdropPath, size: "w1280") {
            _ = await ImageMemoryCache.load(url)
            guard !Task.isCancelled else { return }
            backdropURL = url
        }
    }
}

/// The flowing strip. `Animatable` on `position`, so while it spins SwiftUI re-lays it out every
/// frame from the in-between position — each card turns through the middle and away again.
private struct CoverFlowReel: View, Animatable {
    var position: Double
    let entries: [WatchlistEntry]
    let winnerIndex: Int
    let landed: Bool
    let cardSize: CGSize
    let flat: Bool

    // `nonisolated`: SwiftUI drives `animatableData` off the main actor while interpolating.
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

    private static let corner: CGFloat = 14
    private var url: URL? { TMDBClient.imageURL(path: entry.posterPath, size: "w500") }

    var body: some View {
        VStack(spacing: 6) {
            poster
                .overlay {
                    if isWinner {
                        RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                            .strokeBorder(Theme.Palette.focus, lineWidth: 3)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
            poster
                .scaleEffect(x: 1, y: -1)
                .frame(width: size.width, height: size.height * 0.32, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
        }
        .brightness(dimmed ? -0.35 : 0)
        .animation(Theme.Motion.hero, value: isWinner)
        .animation(Theme.Motion.fade, value: dimmed)
    }

    /// A plain surface while the art is missing — never a spinner flying through the frame.
    private var poster: some View {
        RemoteImage(url: url) { Theme.Palette.surface1 }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
    }
}

/// The winner's title art — TMDB's logo when there is one, the plain name otherwise (which is also
/// what shows while it loads, so a missing logo never reads as a gap).
private struct WinnerTitle: View {
    let logoPath: String?
    let title: String

    var body: some View {
        RemoteImage(url: TMDBClient.imageURL(path: logoPath, size: "w500"), contentMode: .fit) {
            Text(title)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 320, maxHeight: 76, alignment: .bottom)
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
    }
}

/// The winner's backdrop, slowly drifting (scale + a small pan over 24 s, back and forth).
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
        RemoteImage(url: url) { Color.clear }
    }
}
