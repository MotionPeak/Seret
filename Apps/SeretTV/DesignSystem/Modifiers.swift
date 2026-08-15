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
    /// fetches as a fallback — see `RemoteImage`, which re-claims a URL whose prefetch died).
    static func prefetch(_ urls: [URL]) {
        for url in urls where shared.object(forKey: url as NSURL) == nil {
            guard claimInFlight(url) else { continue }   // already downloading — don't fetch it twice
            Task.detached(priority: .utility) {
                defer { releaseInFlight(url) }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let img = UIImage(data: data)?.preparingForDisplay() else { return }
                shared.setObject(img, forKey: url as NSURL, cost: cost(of: img))
            }
        }
    }

    /// URLs currently being fetched, so the same poster is not downloaded and decoded twice.
    ///
    /// Nothing coordinated the prefetch with `RemoteImage`'s own `.task`, or with a second prefetch
    /// of the same rail, and the cache is only populated at the END of a download — so every still
    /// and headshot a screen warmed was routinely fetched and decoded two or three times over,
    /// which on a rail of thirty images is most of what made a page feel slow to settle.
    private nonisolated(unsafe) static let inFlight = NSMutableSet()
    private static let inFlightLock = NSLock()

    static func claimInFlight(_ url: URL) -> Bool {
        inFlightLock.withLock {
            guard !inFlight.contains(url) else { return false }
            inFlight.add(url)
            return true
        }
    }
    static func releaseInFlight(_ url: URL) {
        inFlightLock.withLock { inFlight.remove(url) }
    }
    private static func isInFlight(_ url: URL) -> Bool {
        inFlightLock.withLock { inFlight.contains(url) }
    }

    /// Wait for whoever already claimed `url` to finish, and hand back what they cached. Bounded,
    /// so a fetch that dies without publishing degrades to an empty tile rather than a hung task.
    static func awaitCached(_ url: URL, attempts: Int = 40) async -> UIImage? {
        for _ in 0..<attempts {
            if let image = shared.object(forKey: url as NSURL) { return image }
            if !isInFlight(url) { break }              // they finished, or failed
            try? await Task.sleep(for: .milliseconds(50))
        }
        return shared.object(forKey: url as NSURL)
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
            // Claim it, so a prefetch of the same rail does not fetch and decode this one again.
            // Losing the claim means someone else is already fetching this exact image — wait for
            // their result rather than starting a second download. Waiting is not optional: `body`
            // reads the cache synchronously, so without setting `loaded` here nothing would
            // re-render when their copy landed and this tile would stay on its placeholder.
            if !ImageMemoryCache.claimInFlight(url) {
                if let theirs = await ImageMemoryCache.awaitCached(url) { loaded = theirs; return }
                // Their fetch failed, or outran the wait. Take the claim and do it ourselves —
                // giving up here left the tile on its placeholder for good, because `body` reads
                // the cache synchronously and nothing would re-render it.
                guard ImageMemoryCache.claimInFlight(url) else { return }
            }
            defer { ImageMemoryCache.releaseInFlight(url) }
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
