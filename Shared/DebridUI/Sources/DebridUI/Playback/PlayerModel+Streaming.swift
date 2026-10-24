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
        // Superseded or torn down during the open: whoever cancelled this load looked for a handle
        // to close before this one existed, so it is ours to close.
        guard !Task.isCancelled else {
            Task { await streamProxy.close(handle) }
            return upstream
        }
        streamHandle = handle
        return handle.url
    }

    /// Re-unrestrict for the cache when RD says the link it holds has expired.
    ///
    /// Under the same per-attempt deadline as a load: a refresh that hangs would hold every read
    /// waiting on it — the film frozen with no error and nothing to retry. A timeout is reported
    /// to the cache as a failed refresh, which it treats as RD failing for now.
    func freshLink(_ link: String) async throws -> URL {
        try await withDeadline(unrestrictAttemptTimeout) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.unrestrict(link)
        }
    }

    /// Let the current session go: it keeps its resume region and frees its RAM.
    func closeStream() {
        guard let handle = streamHandle, let streamProxy else { return }
        streamHandle = nil
        Task { await streamProxy.close(handle) }
    }

    /// Why the cache says RD is not serving this stream, if it says so: a refusal, or RD failing
    /// for now. libvlc reports either as a plain end of file.
    func streamFailure() async -> UpstreamFailure? {
        guard let handle = streamHandle, let streamProxy else { return nil }
        return await streamProxy.upstreamFailure(handle)
    }

    /// What to tell the viewer when the cache saw RD REFUSE this stream; nil when it did not —
    /// including when RD is only failing for now, which is a reason to reopen, not to give up.
    func streamRefusal() async -> String? {
        guard case .refused(let failure)? = await streamFailure() else { return nil }
        return Self.refusalMessage(failure, provider: currentProvider)
    }

    /// In the terms of the provider the version came from.
    static func refusalMessage(_ failure: StreamError, provider: DebridProvider) -> String {
        let name = provider.displayName
        switch failure {
        case .upstreamStatus(let status) where status == 404 || status == 410:
            return "\(name) no longer has this file."
        case .upstreamStatus(let status):
            return "\(name) stopped sending this file (HTTP \(status))."
        default:
            return "\(name) stopped sending this file."
        }
    }

    /// The provider (or the network) failing for longer than the app can wait it out — said
    /// plainly, since nothing is wrong with the file and Retry is exactly the right next step.
    static func unreachableMessage(_ provider: DebridProvider) -> String {
        "\(provider.displayName) isn't responding right now. Check your connection, then try again."
    }

    /// The first frame is on screen: what the session has read is what the next open will need.
    func markStreamPlaybackStarted() {
        guard let handle = streamHandle, let streamProxy else { return }
        Task { await streamProxy.markPlaybackStarted(handle) }
    }
}
