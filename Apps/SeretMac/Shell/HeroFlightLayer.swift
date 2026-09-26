import DebridCore
import SwiftUI

extension EnvironmentValues {
    /// Harness-only (`flight` / `flightback`): pins the flyer at an exact progress instead of
    /// running the real spring, so a mid-flight frame can be screenshotted as a still.
    @Entry var previewFlightProgressOverride: Double? = nil
}

/// The flyer itself, driven by `progress` alone (0 = the poster's frame, 1 = the hero's). Marked
/// `Animatable` so `HeroFlightDriver`'s `withAnimation` interpolates it frame by frame instead of
/// jumping straight to the target.
struct HeroFlightLayer: View, Animatable {
    let flight: HeroFlight
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var rect: CGRect { HeroFlightGeometry.frame(from: flight.from, to: flight.to, progress: progress) }
    private var radius: CGFloat { HeroFlightGeometry.cornerRadius(progress: progress) }
    private var posterOpacity: Double { HeroFlightGeometry.posterOpacity(progress: progress) }
    private var backdropOpacity: Double { HeroFlightGeometry.backdropOpacity(progress: progress) }

    var body: some View {
        ZStack {
            posterLayer.opacity(posterOpacity)
            HeroBackdrop(url: flight.backdropURL).opacity(backdropOpacity)
        }
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .position(x: rect.midX, y: rect.midY)
        // Nothing in the flight is ever hit-testable — a click mid-flight reaches whatever is
        // really underneath it (the page or the grid), never the flyer itself.
        .allowsHitTesting(false)
    }

    /// The poster art, from the memory cache when it is already there (the common case — the tile
    /// just rendered it) so the flyer never flashes a placeholder; `RemoteImage` covers the rest.
    @ViewBuilder private var posterLayer: some View {
        if let url = flight.posterURL, let cached = ImageMemoryCache.shared.object(forKey: url as NSURL) {
            Image(decorative: cached.cgImage, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            RemoteImage(url: flight.posterURL, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }
}

/// Owns the one `@State` progress value `HeroFlightLayer` animates, and fires it the instant this
/// view appears — a fresh instance per flight (`MainShell` keys it by `flight.id`), so replacing a
/// flight mid-air (a second open, or a back pressed mid-forward) always starts a clean spring from
/// wherever THIS flight's own `from`/`to` say to start.
struct HeroFlightDriver: View {
    let flight: HeroFlight
    var progressOverride: Double?
    let onLand: (UUID) -> Void

    @State private var progress: Double

    init(flight: HeroFlight, progressOverride: Double?, onLand: @escaping (UUID) -> Void) {
        self.flight = flight
        self.progressOverride = progressOverride
        self.onLand = onLand
        _progress = State(initialValue: progressOverride ?? (flight.direction == .forward ? 0 : 1))
    }

    var body: some View {
        HeroFlightLayer(flight: flight, progress: progressOverride ?? progress)
            .onAppear {
                guard progressOverride == nil else { return }
                let target = flight.direction == .forward ? 1.0 : 0.0
                withAnimation(Theme.Motion.flight, completionCriteria: .logicallyComplete) {
                    progress = target
                } completion: {
                    onLand(flight.id)
                }
            }
    }
}

#if DEBUG
extension ShellModel {
    /// Harness-only: pins a flight directly, bypassing `open()`/`pendingFlightSource` — the
    /// `-uiPreview flight`/`flightback` cases need an exact, reproducible mid-flight frame rather
    /// than depending on a real tile's rendered position (which a dictionary's iteration order
    /// cannot promise is stable across runs).
    func previewPinFlight(_ flight: HeroFlight) { self.flight = flight }
}
#endif
