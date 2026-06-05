import VLCKit
import CoreGraphics

/// Fetches a single video frame at a fractional position, for the scrub preview.
///
/// Uses VLCKit's `VLCMediaThumbnailer`, which opens its own short-lived decode of the (remote)
/// media and decodes one frame near `fraction`. This is best-effort: on a large remote stream it
/// can be slow, so callers debounce to "on settle" and show a timecode/spinner until a frame lands.
/// Only the latest request is kept; superseded thumbnailers are released.
@MainActor
final class ThumbnailProvider {
    private var current: (thumbnailer: VLCMediaThumbnailer, delegate: Delegate)?

    /// A frame at `fraction` (0–1) of `url`, or nil on timeout/failure.
    func frame(url: URL, fraction: Double,
               size: CGSize = CGSize(width: 256, height: 144)) async -> CGImage? {
        let box: ImageBox? = await withCheckedContinuation { continuation in
            guard let media = VLCMedia(url: url) else { continuation.resume(returning: nil); return }
            let delegate = Delegate { continuation.resume(returning: $0) }
            let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: delegate)
            thumbnailer.snapshotPosition = Float(min(max(0, fraction), 1))
            thumbnailer.thumbnailWidth = size.width
            thumbnailer.thumbnailHeight = size.height
            current = (thumbnailer, delegate)               // hold a strong ref while it works
            thumbnailer.fetchThumbnail()
        }
        return box?.image
    }

    /// CGImage isn't `Sendable`; box it to cross the delegate's background thread → the continuation.
    private final class ImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private final class Delegate: NSObject, VLCMediaThumbnailerDelegate {
        private var done = false
        private let onResult: (ImageBox?) -> Void
        init(onResult: @escaping (ImageBox?) -> Void) { self.onResult = onResult }

        func mediaThumbnailer(_ thumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
            finish(ImageBox(thumbnail))
        }
        func mediaThumbnailerDidTimeOut(_ thumbnailer: VLCMediaThumbnailer) { finish(nil) }

        private func finish(_ box: ImageBox?) {
            guard !done else { return }                     // resume the continuation exactly once
            done = true
            onResult(box)
        }
    }
}
