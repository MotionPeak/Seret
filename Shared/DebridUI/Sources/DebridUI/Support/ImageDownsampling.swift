import CoreGraphics
import Foundation
import ImageIO

/// Decoding for the apps' image caches: straight to the pixel size an image is DRAWN at, and the
/// cost accounting that keeps those caches honest.
///
/// `UIImage(data:)` decodes at the file's full size, so a cast headshot fetched at TMDB's `h632`
/// (421 × 632 ≈ 1 MB decoded) occupied three times what its 150-point circle draws. ImageIO's
/// thumbnail path decodes directly at the requested size — less memory AND less decode work.
///
/// A downsampled bitmap is a different object from the full-size one, so the cache key carries the
/// target size (`cacheKey`). Targets are rounded up to a 64-pixel bucket so frames that differ by a
/// point share one entry.
public enum ImageDownsampling {
    /// How the image is fitted into its frame — `fill` needs BOTH sides to cover the frame, `fit`
    /// only the tighter one.
    public enum Fit: Sendable { case fill, fit }

    /// Pixel buckets: a target is rounded UP to a multiple of this.
    public static let bucket: CGFloat = 64

    /// Bytes a decoded RGBA bitmap occupies.
    public static func cost(pixelWidth: Int, pixelHeight: Int) -> Int {
        max(0, pixelWidth) * max(0, pixelHeight) * 4
    }

    /// The target in PIXELS for a frame of `points` drawn at `scale`, rounded up to `bucket`.
    /// Nil for an empty frame — there is nothing to size to.
    public static func targetPixels(points: CGSize, scale: CGFloat) -> CGSize? {
        guard points.width > 0, points.height > 0, scale > 0 else { return nil }
        func up(_ v: CGFloat) -> CGFloat { (v * scale / bucket).rounded(.up) * bucket }
        return CGSize(width: up(points.width), height: up(points.height))
    }

    /// The longest-side bound to hand ImageIO so a `source`-sized image covers `target` — or nil
    /// when the source is already no larger than that (ImageIO never upscales; decoding at the
    /// native size is then right).
    public static func maxPixelSize(source: CGSize, target: CGSize, fit: Fit) -> Int? {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return nil }
        let sx = target.width / source.width, sy = target.height / source.height
        let s = fit == .fill ? max(sx, sy) : min(sx, sy)
        guard s < 1 else { return nil }
        let longest = Int((max(source.width, source.height) * s).rounded(.up))
        return longest < Int(max(source.width, source.height)) ? longest : nil
    }

    /// The cache key for `url` decoded at `target` pixels. The url itself when there is no target,
    /// so a full-size decode keeps the plain url it always had.
    public static func cacheKey(_ url: URL, target: CGSize?) -> URL {
        guard let target, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.fragment = "seret-px=\(Int(target.width))x\(Int(target.height))"
        return parts.url ?? url
    }

    /// Decodes `data`, downsampled to cover `target` pixels when the source is larger. The result
    /// is fully decoded (`kCGImageSourceShouldCacheImmediately`), so drawing it does no further
    /// work on the main thread. Nil when the bytes are not an image.
    public static func decode(_ data: Data, target: CGSize?, fit: Fit = .fill) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let native = max(width, height)

        var maxPixels = native
        if let target, let bound = maxPixelSize(source: CGSize(width: width, height: height),
                                                target: target, fit: fit) {
            maxPixels = bound
        }
        guard maxPixels > 0 else {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The decoded-image budget for a device with `physicalMemory` bytes: 1/32 of it, clamped to
    /// 48–96 MB. A 3 GB Apple TV gets 96 MB; a 2 GB one 64 MB.
    public static func cacheBudget(physicalMemory: UInt64) -> Int {
        let share = Int(min(physicalMemory / 32, UInt64(Int.max)))
        return min(max(share, 48 * 1024 * 1024), 96 * 1024 * 1024)
    }
}
