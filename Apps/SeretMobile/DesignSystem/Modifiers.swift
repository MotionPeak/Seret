import SwiftUI
import UIKit

/// In-memory cache of DECODED images. `AsyncImage` re-fetches AND re-decodes on every appearance —
/// posters flashed their placeholder on every tab switch and grids felt slow. Caching the decoded
/// `UIImage` makes an already-seen image reappear INSTANTLY. (Port of the tvOS fix, `40387ee`.)
enum ImageMemoryCache {
    // NSCache is documented thread-safe; `nonisolated(unsafe)` just tells Swift 6 we know that.
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 96 * 1024 * 1024      // ~96 MB of decoded bitmaps; auto-evicts on pressure
        return c
    }()

    /// What a decoded bitmap actually occupies: width × height × scale² × 4 bytes (RGBA).
    ///
    /// The COMPRESSED `data.count` used to be passed as the cost, which under-reports by 10–20×
    /// (a ~60 KB w500 poster decodes to ~1.5 MB), so the 96 MB ceiling above was really holding
    /// well over a gigabyte of bitmaps. Same fix as tvOS — see that copy for the full story.
    static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }

    /// Warm the cache for a batch of URLs in the background — call when a list's data loads (a
    /// season's episode stills, the Home rails) so cards render with images instead of sitting on
    /// placeholders until each one scrolls into view. No-op for already-cached URLs; failures are
    /// silent (the on-appearance load still fetches as a fallback).
    static func prefetch(_ urls: [URL]) {
        for url in urls where shared.object(forKey: url as NSURL) == nil {
            Task.detached(priority: .utility) {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let img = UIImage(data: data)?.preparingForDisplay() else { return }
                shared.setObject(img, forKey: url as NSURL, cost: cost(of: img))
            }
        }
    }
}

/// An image that crossfades in from its placeholder — backed by `ImageMemoryCache` so an
/// already-shown image reappears instantly (no re-fetch, no re-decode), decoding off the main
/// thread so a full grid doesn't hitch. Wrap with `.frame`/`.clipShape` at the call site exactly
/// like `AsyncImage`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?

    var body: some View {
        // Synchronous cache check (current url first) → no placeholder flash when a page reappears.
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) } ?? loaded
        return Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(Theme.Motion.fade, value: image != nil)
        .onChange(of: url) { loaded = nil }     // a reused cell pointed at a new url → drop the old
        .task(id: url) {
            guard let url, ImageMemoryCache.shared.object(forKey: url as NSURL) == nil else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            // Decode off the main actor — decoding a whole screen of posters on main is what
            // makes a grid feel like it "loads for a long time".
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value
            guard let decoded, !Task.isCancelled else { return }
            ImageMemoryCache.shared.setObject(decoded, forKey: url as NSURL,
                                              cost: ImageMemoryCache.cost(of: decoded))
            loaded = decoded
        }
    }
}

extension RemoteImage where Placeholder == MediaPlaceholder {
    /// Convenience: the standard dark media placeholder (surface + film glyph).
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { MediaPlaceholder() }
    }
}

/// The default loading tile for posters/backdrops/stills — the same surface + film glyph the
/// screens already used, so nothing changes visually while an image loads.
struct MediaPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.Palette.surface2
            Image(systemName: "film").foregroundStyle(Theme.Palette.textTertiary)
        }
    }
}

extension View {
    /// Soft gold halo for active/interactive elements.
    func goldGlow(_ radius: CGFloat = 16, opacity: Double = 0.45) -> some View {
        shadow(color: Color(hex: 0xEBC11D, alpha: opacity), radius: radius)
    }

    /// Dark frosted bar/sheet background (blur + black tint + hairline top).
    func glassBackground(topHairline: Bool = true) -> some View {
        background(.ultraThinMaterial)
            .background(Theme.Palette.canvas.opacity(0.55))
            .overlay(alignment: .top) {
                if topHairline { Theme.Palette.hairline.frame(height: 0.5) }
            }
    }

    /// Tap feedback: scale down on press.
    func pressable() -> some View { buttonStyle(PressableButtonStyle()) }
}

/// Scales content to 0.96 while pressed. Use on tappable cards/posters.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Full-screen Gold Glass canvas wash. Put behind screen content.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.canvas
            Theme.Palette.canvasGlow
        }
        .ignoresSafeArea()
    }
}
