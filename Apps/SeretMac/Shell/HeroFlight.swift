import CoreGraphics
import Foundation

/// The named coordinate space every window-relative frame (a poster tile, the title hero) is
/// measured in, so a flight's `from`/`to` are comparable no matter which view reported them.
enum ShellSpace {
    static let window = "seret.window"
}

/// A poster tile's frame + art, captured at tap time (Decision 10) — the source cell can be
/// recycled or scrolled away mid-flight, so this snapshot is all a flight ever reads from it again.
struct FlightSource: Equatable {
    let tileID: UUID
    let frame: CGRect
    let posterURL: URL?
}

/// The pure geometry behind the poster → backdrop flight: where the flyer sits, how rounded its
/// corners are, and how the poster and backdrop art cross-fade, all as a function of `progress`
/// alone. Nothing here touches SwiftUI, so it is unit-tested directly.
enum HeroFlightGeometry {
    static let startRadius: CGFloat = 12

    /// The title hero's band in window coordinates — it runs the full width, under the sidebar,
    /// starting at the window's top edge.
    static func backdropFrame(window: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: window.width, height: TitlePageLayout.heroHeight(width: window.width))
    }

    enum Plan: Equatable {
        case fly(from: CGRect, to: CGRect)
        case crossFade
    }

    /// `crossFade` when Reduce Motion is on, there is no source, the source is empty, or less than
    /// half of the source's own area sits inside the window.
    static func plan(source: CGRect?, target: CGRect, window: CGSize, reduceMotion: Bool) -> Plan {
        guard !reduceMotion, let source, !source.isEmpty else { return .crossFade }
        let sourceArea = source.width * source.height
        guard sourceArea > 0 else { return .crossFade }
        let windowRect = CGRect(origin: .zero, size: window)
        let intersection = source.intersection(windowRect)
        let visibleArea = intersection.isNull ? 0 : intersection.width * intersection.height
        guard visibleArea / sourceArea >= 0.5 else { return .crossFade }
        return .fly(from: source, to: target)
    }

    /// Linear interpolation — deliberately NOT clamped, so a spring's overshoot past 1 (or below 0)
    /// still moves the frame past `to` (or before `from`) instead of pinning at the edge.
    static func frame(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        CGRect(x: lerp(from.minX, to.minX, progress), y: lerp(from.minY, to.minY, progress),
              width: lerp(from.width, to.width, progress), height: lerp(from.height, to.height, progress))
    }

    /// 12 → 0, floored at 0 so overshoot past progress 1 never goes negative.
    static func cornerRadius(progress: Double) -> CGFloat {
        max(0, startRadius * (1 - CGFloat(progress)))
    }

    /// The poster holds fully opaque through the first 18% of the flight, then fades to 0 by 92%
    /// (mockup 3: a 460 ms cross-fade starting 110 ms into a 620 ms flight), clamped to 0...1
    /// outside that band so an overshooting spring never over- or under-shoots the opacity too.
    static func posterOpacity(progress: Double) -> Double {
        let start = 0.18, end = 0.92
        if progress <= start { return 1 }
        if progress >= end { return 0 }
        return 1 - (progress - start) / (end - start)
    }

    /// The exact complement — the backdrop fades in as the poster fades out.
    static func backdropOpacity(progress: Double) -> Double {
        1 - posterOpacity(progress: progress)
    }
}

/// One flight in flight: a poster growing into the title hero's band, or the reverse. `from`/`to`
/// are always (poster frame, hero frame) regardless of direction — `direction` alone decides
/// whether `HeroFlightLayer` animates progress 0 → 1 or 1 → 0, so the same geometry functions run
/// forward or in reverse.
struct HeroFlight: Identifiable, Equatable {
    enum Direction: Equatable { case forward, back }

    let id = UUID()
    let direction: Direction
    /// The title's `item.id` — what a page checks to know a flight is (or was) headed for it.
    let routeID: String
    let from: CGRect
    let to: CGRect
    let posterURL: URL?
    let backdropURL: URL?
    /// The source tile's identity, so the tile can hide itself while its own flight is up and
    /// `goBack()` can look up that tile's LATEST reported frame. `nil` for a source with no tile
    /// (Home hero, Continue Watching, a Person credit — Decision 10), which never flies at all.
    let tileID: UUID?
    var landed = false
}
