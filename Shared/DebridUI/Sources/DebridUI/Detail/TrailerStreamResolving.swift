import Foundation
import YouTubeKit

/// Resolves a YouTube video key to a direct, AVPlayer-playable stream URL. Seam so `TrailerModel`
/// is testable without YouTubeKit (and so the resolver can be swapped if YouTube extraction moves).
public protocol TrailerStreamResolving: Sendable {
    /// A directly-playable stream URL for the YouTube key, or nil if extraction fails / none.
    func streamURL(youTubeKey: String) async -> URL?
}

/// `TrailerStreamResolving` backed by YouTubeKit. Returns the first PROGRESSIVE (muxed audio+video)
/// stream — YouTube serves a single 360p progressive format today, which AVPlayer plays natively.
/// Higher-res would require stitching separate adaptive streams (out of scope for trailers).
public struct YouTubeKitStreamResolver: TrailerStreamResolving {
    public init() {}

    public func streamURL(youTubeKey: String) async -> URL? {
        guard let streams = try? await YouTube(videoID: youTubeKey).streams else { return nil }
        return streams.first { $0.isProgressive }?.url
    }
}
