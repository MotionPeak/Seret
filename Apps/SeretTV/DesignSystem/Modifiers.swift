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

    /// One image load, end to end: cache → claim → wait for whoever holds the claim → fetch →
    /// decode → cache. `nil` means the image genuinely could not be produced, which is what lets a
    /// caller settle into a "no image" state instead of a spinner that never stops.
    ///
    /// This used to be inlined in `RemoteImage`'s `.task`, where every failure was a bare `return`
    /// and the tile was left on its placeholder for good. The path that actually shipped was a race
    /// with `prefetch()`: prefetch claims the url, `RemoteImage` loses the claim, `awaitCached`
    /// polls for its budget and gives up, the re-claim fails too because the prefetch STILL holds
    /// it — and the load returned having done nothing. Exactly the images whose prefetch outran the
    /// wait hung forever, which is why it was always a consistent minority of tiles.
    ///
    /// So losing the claim twice no longer ends the load: we fetch anyway. A rare duplicate
    /// download costs far less than a tile that never loads.
    static func load(
        _ url: URL,
        waitAttempts: Int = 40,
        fetch: @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) async -> UIImage? {
        if let hit = shared.object(forKey: url as NSURL) { return hit }

        var holdsClaim = claimInFlight(url)
        if !holdsClaim {
            if let theirs = await awaitCached(url, attempts: waitAttempts) { return theirs }
            holdsClaim = claimInFlight(url)     // free by now? take it. Still held? fetch regardless.
        }
        // Only release what we actually took, or we would free someone else's claim.
        defer { if holdsClaim { releaseInFlight(url) } }

        guard let data = try? await fetch(url) else { return nil }
        // Decode off the main actor — decoding a whole screen of posters on main is what made the
        // grid feel like it "loads for a long time".
        let decoded = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
        guard let decoded else { return nil }
        shared.setObject(decoded, forKey: url as NSURL, cost: cost(of: decoded))
        return decoded
    }
}

/// An image that crossfades in from a dark surface placeholder — no hard pop-in (the #1 source of
/// the "jumpy / loads pages" feel). Backed by `ImageMemoryCache` so a poster already shown reappears
/// instantly (no re-fetch, no re-decode); decodes off the main thread so a full grid doesn't hitch.
/// Wrap with `.frame`/`.clipShape` at the call site exactly like `AsyncImage`.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Receives `true` once the load has genuinely failed, so the placeholder can stop pretending
    /// to be busy. A tile that spins forever reads as "the app is broken"; a settled one reads as
    /// "there is no artwork for this".
    @ViewBuilder var placeholder: (_ failed: Bool) -> Placeholder
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        // Synchronous cache check (current url first) → no placeholder flash when a page reappears.
        let image = url.flatMap { ImageMemoryCache.shared.object(forKey: $0 as NSURL) } ?? loaded
        return Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                placeholder(failed)
            }
        }
        .animation(Theme.Anim.imageFade, value: image != nil)
        .onChange(of: url) { loaded = nil; failed = false }   // reused cell, new url → drop the old
        .task(id: url) {
            guard let url, ImageMemoryCache.shared.object(forKey: url as NSURL) == nil else { return }
            failed = false
            let image = await ImageMemoryCache.load(url)
            guard !Task.isCancelled else { return }
            if let image { loaded = image } else { failed = true }
        }
    }
}

extension RemoteImage where Placeholder == PosterPlaceholder {
    /// Convenience: the standard dark poster/backdrop placeholder.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) { PosterPlaceholder(failed: $0) }
    }
}

/// The default tile for posters/backdrops — a palette surface that spins while it is genuinely
/// loading and settles to a muted glyph once the load has failed, so a broken image never
/// impersonates a busy one.
struct PosterPlaceholder: View {
    var failed = false
    var body: some View {
        ZStack {
            Theme.Palette.surface2
            if failed {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.textSecondary.opacity(0.45))
            } else {
                ProgressView().tint(Theme.Palette.gold)
            }
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
