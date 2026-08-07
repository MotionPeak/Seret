import SwiftUI
import UIKit

extension View {
    /// Soft gold bloom behind a view. A `radius` of 0 disables it.
    func goldGlow(_ radius: CGFloat, opacity: Double = 0.5) -> some View {
        shadow(color: Theme.Palette.gold.opacity(radius > 0 ? opacity : 0), radius: radius)
    }
}

/// In-memory cache of DECODED images. `AsyncImage` re-decodes on every appearance — which flashed
/// the placeholder and re-loaded every poster when you switched between Movies/TV/etc. Caching the
/// decoded `UIImage` makes an already-seen poster reappear INSTANTLY.
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
    /// (a ~60 KB w500 poster decodes to ~1.5 MB, a w1280 backdrop to ~3.7 MB). The 96 MB ceiling
    /// above was therefore holding well over a gigabyte of bitmaps, which on a 3 GB Apple TV left
    /// the app permanently at the edge of memory pressure — that is what starved JavaScriptCore of
    /// heap when a trailer was resolved (JSC aborts outright on exhaustion, uncatchable) and what
    /// put the process within reach of a jetsam kill.
    static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }

    /// Warm the cache for a batch of URLs in the background — call when a list's data loads (e.g. a
    /// season's episode stills) so the cards render with images instead of sitting grey until each one
    /// scrolls into view. No-op for already-cached URLs; failures are silent (the on-appear load still
    /// fetches as a fallback).
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

/// An image that crossfades in from a dark surface placeholder — no hard pop-in (the #1 source of
/// the "jumpy / loads pages" feel). Backed by `ImageMemoryCache` so a poster already shown reappears
/// instantly (no re-fetch, no re-decode); decodes off the main thread so a full grid doesn't hitch.
/// Wrap with `.frame`/`.clipShape` at the call site exactly like `AsyncImage`.
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
        .animation(Theme.Anim.imageFade, value: image != nil)
        .onChange(of: url) { loaded = nil }     // a reused cell pointed at a new url → drop the old
        .task(id: url) {
            guard let url, ImageMemoryCache.shared.object(forKey: url as NSURL) == nil else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            // Decode off the main actor — decoding a whole screen of posters on main is what made
            // the grid feel like it "loads for a long time".
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

extension RemoteImage where Placeholder == PosterPlaceholder {
    /// Convenience: the standard dark poster/backdrop placeholder.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { PosterPlaceholder() }
    }
}

/// The default loading tile for posters/backdrops — a palette surface + gold spinner, so empty
/// tiles read as "loading" and stay on-brand instead of flashing a raw system grey.
struct PosterPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.Palette.surface2
            ProgressView().tint(Theme.Palette.gold)
        }
    }
}

/// A centered, on-brand loading state (gold spinner + optional label) for full-screen waits.
struct SeretLoader: View {
    var label: String?
    var body: some View {
        VStack(spacing: 20) {
            ProgressView().tint(Theme.Palette.gold).controlSize(.large)
            if let label {
                Text(label).calloutText().foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
