import DebridCore
import DebridUI
import SwiftUI

/// "Surprise Me" — spins through the watchlist and lands on one film to watch.
///
/// The winner is chosen by `WatchlistRandomizer` BEFORE anything moves, and the reel is built to
/// end on it. The animation is therefore pure presentation: it cannot change the answer, and a
/// reel interrupted half-way still names the film the picker chose.
struct WatchlistSpinScreen: View {
    let spin: WatchlistRandomizer.Spin
    let onWatch: (WatchlistEntry) -> Void
    let onSpinAgain: () -> Void
    let onClose: () -> Void

    /// How far along the reel the animation currently is, in frames. Animating this ONE value is
    /// what makes the deceleration real rather than a guess: SwiftUI interpolates it along the
    /// timing curve and every poster's position, scale and dimming is derived from it, so the
    /// whole reel slows together.
    @State private var position: Double = 0
    @State private var landed = false
    @FocusState private var focus: Field?

    private enum Field { case watch, again }

    /// Fast at first, then a long settle — the shape of a wheel losing momentum. The last few
    /// frames crawl, which is where the tension is.
    private var spinCurve: Animation { .timingCurve(0.08, 0.85, 0.12, 1.0, duration: 3.1) }

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 0) {
                Text(landed ? "Tonight you're watching" : "Finding you something…")
                    .sectionTitle()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, 40)

                reel
                    .frame(height: SpinReel.posterHeight * 1.25)

                landedDetail
                    .padding(.top, 44)
            }
            .padding(.horizontal, Theme.Layout.contentMargin)
        }
        .onAppear(perform: start)
        // Re-spinning replaces this screen's `spin`, so restart from the top when it changes.
        .onChange(of: spin.winner.slug) { _, _ in start() }
        // MENU backs out without picking anything.
        .onExitCommand(perform: onClose)
    }

    private func start() {
        landed = false
        position = 0
        withAnimation(spinCurve) { position = Double(spin.winnerIndex) }
        // The reel is `.timingCurve`-driven, so "it has stopped" is a matter of the clock rather
        // than something the animation reports back. Matching the duration is what keeps the
        // result from appearing over posters that are still moving.
        Task {
            try? await Task.sleep(for: .seconds(3.1))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Anim.heroSpring) { landed = true }
            // One turn after `landed`, so the buttons have actually been inserted — focus cannot
            // be assigned to a view that does not exist yet.
            try? await Task.sleep(for: .milliseconds(120))
            focus = .watch
        }
    }

    private var reel: some View {
        ZStack {
            // The reel stays on screen at rest. It settles with films either side of the winner,
            // the way a wheel stops with the neighbouring symbols still showing — which is the
            // whole reason the reel carries frames past the winner rather than ending on it.
            SpinReel(frames: spin.reel, position: position)
            // The centre marker the reel runs under: what the film lands *in*.
            RoundedRectangle(cornerRadius: Theme.Layout.posterCorner + 4, style: .continuous)
                .strokeBorder(Theme.Palette.gold, lineWidth: landed ? 6 : 3)
                .frame(width: SpinReel.posterWidth + 16, height: SpinReel.posterHeight + 16)
                .goldGlow(landed ? 26 : 10, opacity: landed ? 0.9 : 0.35)
                .animation(Theme.Anim.heroSpring, value: landed)
                .allowsHitTesting(false)
        }
        .animation(Theme.Anim.pageFade, value: landed)
    }

    /// Fixed height, conditional content.
    ///
    /// NOT `.opacity(landed ? 1 : 0)`, which is what this was: a fully transparent view cannot
    /// take focus on tvOS, so "Watch It" was assigned focus mid-fade and the assignment was
    /// silently dropped — the result appeared with the remote pointing at nothing. Reserving the
    /// space with a frame keeps the reel from jumping while letting the buttons genuinely not
    /// exist until there is something to press.
    @ViewBuilder private var landedDetail: some View {
        ZStack {
            if landed {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(WatchlistName.stripYear(from: spin.winner.name))
                            .screenTitle()
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        if let year = spin.winner.year {
                            Text(String(year))
                                .calloutText()
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }

                    HStack(spacing: 24) {
                        Button("Watch It") { onWatch(spin.winner) }
                            .buttonStyle(SeretActionButtonStyle())
                            .focused($focus, equals: .watch)
                        Button("Spin Again", action: onSpinAgain)
                            .buttonStyle(SeretPillStyle(selected: false))
                            .focused($focus, equals: .again)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(height: 210)
        .animation(Theme.Anim.pageFade, value: landed)
    }
}

/// The row of posters, laid out from one animatable position.
///
/// `Animatable` rather than animating each poster: SwiftUI interpolates `position` along the
/// timing curve and hands this view every intermediate value, so the posters are placed per frame
/// from a single source of truth. That is what lets them scale and dim by distance from the centre
/// while decelerating together.
private struct SpinReel: View, Animatable {
    let frames: [WatchlistEntry]
    var position: Double

    static let posterWidth: CGFloat = 260
    static let posterHeight: CGFloat = 390
    /// Centre-to-centre spacing. Wider than the poster so neighbours read as separate cards.
    private static let pitch: CGFloat = 300
    /// Only the few frames either side of centre are ever on screen; drawing the rest would be
    /// 26 posters' worth of image decoding for nothing.
    private static let visibleRadius = 3

    // `nonisolated`: SwiftUI drives `animatableData` off the main actor while interpolating, and
    // under Swift 6 a plain conformance on a View would cross isolation. The value is a Double on
    // a value type, so there is nothing to race on.
    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(window, id: \.self) { index in
                let distance = Double(index) - position
                poster(frames[index])
                    .offset(x: CGFloat(distance) * Self.pitch)
                    // The centred card is full size and bright; its neighbours sit back.
                    .scaleEffect(scale(for: distance))
                    .opacity(opacity(for: distance))
                    .zIndex(-abs(distance))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// The indices worth drawing at this position.
    private var window: [Int] {
        let centre = Int(position.rounded())
        let lower = max(0, centre - Self.visibleRadius)
        let upper = min(frames.count - 1, centre + Self.visibleRadius)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    private func scale(for distance: Double) -> Double {
        max(0.7, 1.0 - abs(distance) * 0.12)
    }

    private func opacity(for distance: Double) -> Double {
        max(0.0, 1.0 - abs(distance) * 0.26)
    }

    private func poster(_ entry: WatchlistEntry) -> some View {
        RemoteImage(url: TMDBClient.imageURL(path: entry.posterPath, size: "w500"))
            .frame(width: Self.posterWidth, height: Self.posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.posterCorner, style: .continuous))
    }
}
