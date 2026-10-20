import CoreImage
import DebridCore
import SwiftUI
import UIKit

/// The page background of a browse page: the focused title's art, Plex "ultrablur" style.
///
/// Two layers per title — a heavily blurred, saturated, darkened wash of the backdrop over the
/// whole screen, and the sharp backdrop in the trailing 70% × top 76%, dissolving into the wash
/// towards the leading and bottom edges — under a leading + bottom legibility shade so the header
/// text and the rails always read.
///
/// **Cheap on purpose.** A live `.blur` over a full-screen layer is re-run by the compositor on
/// every frame anything under it moves, and that is exactly how a page drops frames on a real
/// Apple TV. The wash is instead rendered ONCE per title from TMDB's 300-pixel backdrop with Core
/// Image, cached, and drawn as a plain stretched bitmap — a heavy blur hides any upscaling, so it
/// looks the same and costs a texture.
///
/// **It never flashes while focus glides.** A new title's plate is shown only once its images
/// are in memory; until then the previous plate stays up. Every plate is its own layer with its
/// own opacity, keyed by a serial number, and each new one fades in OVER whatever is already
/// there — so a change that lands mid-fade never restarts or pops the plate below it: that plate
/// just carries on fading in underneath. A plate is removed only once the one above it has fully
/// covered it. A nil path is a plate too — plain canvas — so "no art" fades the same way.
///
/// `showsArt: false` draws the wash alone — Plex's library-grid background. A grid has no header
/// in the leading third for the art to sit beside: its posters, captions and status line run the
/// full width, and over the sharp art the light parts of a backdrop swallowed them (measured on the
/// Watchlist: the partner line vanished into a bright poster-like backdrop).
struct UltrablurBackdrop: View {
    let backdropPath: String?
    var showsArt = true

    /// Bottom to top. Usually one; two or three while fades overlap.
    @State private var plates: [BackdropPlate] = []
    @State private var nextSerial = 0

    var body: some View {
        ZStack {
            Theme.Palette.canvas
            ForEach(plates) { plate in
                Group {
                    if let path = plate.path {
                        UltrablurPlate(path: path, showsArt: showsArt)
                    } else {
                        Theme.Palette.canvas
                    }
                }
                // In: fades over what is below. Out: only ever removed once covered, so instantly.
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            LegibilityShade()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: backdropPath) { await show(backdropPath) }
    }

    private func show(_ path: String?) async {
        // Already the plate on top (or, for nil, nothing has ever been shown): nothing to do.
        if let top = plates.last { guard top.path != path else { return } } else if path == nil { return }
        // Hold the current plate until this one can draw — never fade towards an empty layer.
        if let path { await UltrablurPlates.warm(path, sharp: showsArt) }
        guard !Task.isCancelled else { return }

        let plate = BackdropPlate(serial: nextSerial, path: path)
        nextSerial += 1
        withAnimation(Theme.Anim.backdrop) { plates.append(plate) }

        // Once this plate is fully opaque, everything under it is invisible: drop it. Unstructured
        // on purpose — a newer path cancels this task, and the plates below must still go.
        let serial = plate.serial
        Task { @MainActor in
            try? await Task.sleep(for: Self.coverDelay)
            guard let index = plates.firstIndex(where: { $0.serial == serial }), index > 0 else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { plates.removeFirst(index) }
        }
    }

    /// The backdrop fade plus a margin, so a plate is fully opaque before what it covers goes.
    private static let coverDelay: Duration = .milliseconds(750)
}

/// One layer of the backdrop stack: a title's art, or (nil) the plain canvas.
private struct BackdropPlate: Identifiable {
    let serial: Int
    let path: String?
    var id: Int { serial }
}

/// One title's two layers. Reads both images from the caches synchronously, so a plate the
/// backdrop has warmed draws complete on its first frame.
private struct UltrablurPlate: View {
    let path: String
    /// Fixed for the backdrop's life — never a swap under focus.
    let showsArt: Bool

    /// The sharp art's share of the screen, from the approved mockup.
    private static let artWidth: CGFloat = 0.70
    private static let artHeight: CGFloat = 0.76

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let wash = UltrablurPlates.cachedWash(path) {
                    Image(uiImage: wash)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                if showsArt { sharpArt(geo.size) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
        }
    }

    /// The sharp backdrop in the trailing 70% × top 76%, dissolving towards the leading and bottom
    /// edges.
    private func sharpArt(_ size: CGSize) -> some View {
        RemoteImage(url: TMDBClient.imageURL(path: path, size: "w1280"), contentMode: .fill) { _ in
            Color.clear
        }
        .frame(width: size.width * Self.artWidth, height: size.height * Self.artHeight)
        .clipped()
        .mask {
            // Opaque from the trailing edge to 45% in, gone at the leading edge — and the
            // same from the top down to 45% above the bottom. The two multiply.
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.55)],
                           startPoint: .leading, endPoint: .trailing)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.55),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
    }
}

/// Darkens the leading third and the bottom of the screen so white text and posters always read
/// over any art. Values from the approved mockup.
private struct LegibilityShade: View {
    private static let ink = Theme.Palette.shadeInk

    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Self.ink.opacity(0.90), location: 0),
                                   .init(color: Self.ink.opacity(0.50), location: 0.36),
                                   .init(color: Self.ink.opacity(0), location: 0.62)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: Self.ink.opacity(0.92), location: 0),
                                   .init(color: Self.ink.opacity(0.35), location: 0.45),
                                   .init(color: Self.ink.opacity(0), location: 0.62)],
                           startPoint: .bottom, endPoint: .top)
        }
    }
}

// MARK: - Plate cache

/// The rendered washes, plus the warm-up that a plate waits on before it is shown.
///
/// Loads are coalesced per path: the backdrop and the page's preview settle both warm the same
/// title at the same moment, and must not render it twice.
@MainActor
enum UltrablurPlates {
    private static let washes: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Costed in decoded bytes like `ImageMemoryCache`, so pressure evicts by real size.
        cache.totalCostLimit = 16 * 1024 * 1024     // a 300×169 wash is ~200 KB: ~80 titles
        return cache
    }()
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    static func cachedWash(_ path: String) -> UIImage? {
        washes.object(forKey: path as NSString)
    }

    /// Brings both layers of `path` into memory: the rendered wash and (`sharp`) the decoded sharp
    /// art. Returns when both have loaded or failed.
    static func warm(_ path: String, sharp: Bool = true) async {
        guard sharp else { _ = await wash(for: path); return }
        async let wash = wash(for: path)
        async let art = sharpArt(for: path)
        _ = await (wash, art)
    }

    private static func sharpArt(for path: String) async -> UIImage? {
        guard let url = TMDBClient.imageURL(path: path, size: "w1280") else { return nil }
        return await ImageMemoryCache.load(url)
    }

    /// The blurred wash for `path`, rendered from TMDB's `w300` image. Nil when the image could
    /// not be fetched; a later call tries again.
    static func wash(for path: String) async -> UIImage? {
        if let hit = cachedWash(path) { return hit }
        if let running = inFlight[path] { return await running.value }
        let task = Task { () -> UIImage? in
            guard let url = TMDBClient.imageURL(path: path, size: "w300"),
                  let small = await ImageMemoryCache.load(url) else { return nil }
            return await Task.detached(priority: .userInitiated) { UltrablurRenderer.render(small) }.value
        }
        inFlight[path] = task
        let wash = await task.value
        inFlight[path] = nil
        if let wash { washes.setObject(wash, forKey: path as NSString, cost: ImageMemoryCache.cost(of: wash)) }
        return wash
    }
}

/// Core Image recipe for the wash: blur → saturate → darken, at the small image's own size.
enum UltrablurRenderer {
    /// Gaussian sigma in pixels of the 300px-wide source. The mockup's `blur(110px)` over a
    /// ~2240pt layer is ~15px at this scale; a touch less keeps a hint of the art's shapes.
    static let sigma: Double = 13
    static let saturation: Double = 1.7
    /// Multiplied into every channel — the mockup's `brightness(.6)`. A multiply (rather than
    /// an additive brightness) keeps dark art from crushing to flat black.
    static let brightness: CGFloat = 0.6

    /// Thread-safe and expensive to make: one for every render.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let extent = input.extent
        let output = input
            .clampedToExtent()      // blur the edges against themselves, not against transparency
            .applyingGaussianBlur(sigma: sigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: brightness, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: brightness, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: brightness, w: 0),
            ])
            .cropped(to: extent)
        guard let rendered = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
