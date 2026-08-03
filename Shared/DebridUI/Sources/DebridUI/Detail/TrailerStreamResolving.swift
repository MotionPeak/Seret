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

/// Remembers resolved stream URLs and coalesces concurrent lookups for the same video.
///
/// This is a stability measure, not just a speed one. YouTubeKit's local extraction descrambles the
/// stream signature by evaluating YouTube's player script in JavaScriptCore, and JSC **aborts the
/// process** when its heap is exhausted — `JSC::handleResourceExhaustion` calls CRASH() and there is
/// no Swift error to catch. That abort is in this app's crash reports, on the 3 GB Apple TV. Since
/// the evaluation cannot be made safe, the only lever is to run it as rarely as possible: once per
/// video per session, never twice at the same time.
///
/// Failures are cached too — otherwise a title whose extraction fails would re-run the script on
/// every press of Trailer, which is the worst case for a crash caused by running it at all. The cost
/// is that a resolution which failed for a transient reason stays failed until the app restarts.
public actor CachingTrailerStreamResolver: TrailerStreamResolving {
    private let base: TrailerStreamResolving
    /// Nested optional on purpose: a present-but-nil entry is a REMEMBERED failure.
    private var cached: [String: URL?] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]

    public init(base: TrailerStreamResolving) { self.base = base }

    public func streamURL(youTubeKey: String) async -> URL? {
        if let remembered = cached[youTubeKey] { return remembered }
        if let running = inFlight[youTubeKey] { return await running.value }
        let task = Task { [base] in await base.streamURL(youTubeKey: youTubeKey) }
        inFlight[youTubeKey] = task
        let url = await task.value
        inFlight[youTubeKey] = nil
        cached[youTubeKey] = url
        return url
    }
}
