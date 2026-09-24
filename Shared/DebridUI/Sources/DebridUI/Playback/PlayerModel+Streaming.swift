import Foundation
import DebridCore

/// The stream cache (DebridCore's `StreamProxy`) in front of Real-Debrid.
///
/// libvlc used to open RD's link directly, and every reposition inside the file — each skip, and
/// every step of the MKV demuxer's keyframe hunt — was a new TLS connection to RD at ~460ms. With
/// the cache, libvlc opens a loopback URL instead: rewinds and the hunt are served from RAM, and a
/// film opened before reads its index from disk.
extension PlayerModel {

    /// Open a cache session for the source about to load, and return the URL libvlc should play.
    /// RD's link itself when there is no cache — or when the cache could not start.
    func openStream(for upstream: URL) async -> URL {
        closeStream()
        guard let streamProxy else { return upstream }
        let link = currentSource.restrictedLink
        let handle = await streamProxy.open(
            upstream: upstream, fileKey: WatchKey.source(currentSource),
            refreshUpstream: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.freshLink(link)
            })
        streamHandle = handle
        return handle.url
    }

    /// Re-unrestrict for the cache when RD says the link it holds has expired.
    func freshLink(_ link: String) async throws -> URL {
        try await unrestrict(link)
    }

    /// Let the current session go: it keeps its resume region and frees its RAM.
    func closeStream() {
        guard let handle = streamHandle, let streamProxy else { return }
        streamHandle = nil
        Task { await streamProxy.close(handle) }
    }

    /// The first frame is on screen: what the session has read is what the next open will need.
    func markStreamPlaybackStarted() {
        guard let handle = streamHandle, let streamProxy else { return }
        Task { await streamProxy.markPlaybackStarted(handle) }
    }
}
