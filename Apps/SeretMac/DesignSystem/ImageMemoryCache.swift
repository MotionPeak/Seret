import CoreGraphics
import Foundation
import ImageIO

/// A fully decoded bitmap. A final class so `NSCache` can hold it; immutable, so it may cross actors.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    init(cgImage: CGImage) { self.cgImage = cgImage }
    /// What the bitmap really occupies — not the compressed size, which under-reports 10–20×.
    var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// In-memory cache of DECODED images, so an already-seen poster reappears instantly (no re-fetch, no
/// re-decode) and a grid scrolls without decoding on the main thread. Port of the iPhone/tvOS cache,
/// including their fixes: accurate cost, an in-flight set so one image is not fetched twice, and a
/// load that never ends in a silent dead tile.
enum ImageMemoryCache {
    // NSCache is documented thread-safe; `nonisolated(unsafe)` tells Swift 6 we know that.
    nonisolated(unsafe) static let shared: NSCache<NSURL, DecodedImage> = {
        let cache = NSCache<NSURL, DecodedImage>()
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    /// Decode fully, here: `kCGImageSourceShouldCacheImmediately` makes ImageIO decode now rather than
    /// on first draw, which would land on the main thread mid-scroll.
    static func decode(_ data: Data) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return DecodedImage(cgImage: image)
    }

    /// Warm the cache for a batch of URLs in the background. Failures are silent: the on-appearance
    /// load still fetches as a fallback.
    static func prefetch(_ urls: [URL]) {
        for url in urls where shared.object(forKey: url as NSURL) == nil {
            guard claimInFlight(url) else { continue }
            Task.detached(priority: .utility) {
                defer { releaseInFlight(url) }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = decode(data) else { return }
                shared.setObject(image, forKey: url as NSURL, cost: image.cost)
            }
        }
    }

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

    /// One load, end to end: cache → claim → wait for whoever holds the claim → fetch → decode → cache.
    /// `nil` means the image genuinely could not be produced. Losing the claim twice still fetches: a
    /// rare duplicate download costs far less than a tile that never loads.
    static func load(
        _ url: URL,
        waitAttempts: Int = 40,
        fetch: @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }
    ) async -> DecodedImage? {
        if let hit = shared.object(forKey: url as NSURL) { return hit }

        var holdsClaim = claimInFlight(url)
        if !holdsClaim {
            if let theirs = await awaitCached(url, attempts: waitAttempts) { return theirs }
            holdsClaim = claimInFlight(url)
        }
        defer { if holdsClaim { releaseInFlight(url) } }

        guard let data = try? await fetch(url) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) { decode(data) }.value
        guard let decoded else { return nil }
        shared.setObject(decoded, forKey: url as NSURL, cost: decoded.cost)
        return decoded
    }

    /// Wait (bounded) for whoever claimed `url` to publish it.
    static func awaitCached(_ url: URL, attempts: Int = 40) async -> DecodedImage? {
        for _ in 0..<attempts {
            if let image = shared.object(forKey: url as NSURL) { return image }
            if !isInFlight(url) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return shared.object(forKey: url as NSURL)
    }
}
