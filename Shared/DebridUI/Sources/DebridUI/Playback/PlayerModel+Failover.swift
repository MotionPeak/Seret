import Foundation
import DebridCore

/// Moving to the other debrid provider when the one playing is down.
///
/// On 2026-10-24 Real-Debrid's file servers answered 503 to every fetch while its API worked, and
/// nothing could be watched. With both accounts signed in, a title can have versions on Real-Debrid
/// AND TorBox — so when the current version's provider is failing for now (not refusing: a refusal
/// is that provider's answer about this file), the player loads the other provider's version by
/// itself, at the same place, and says so.
///
/// It comes after the provider's own recovery — the unrestrict's retries, the silent reopen,
/// `finish()`'s reopen at the playhead — and in place of the error those would end on. Once per
/// load, so two providers both down end on the error screen instead of bouncing between them.
extension PlayerModel {

    /// The provider of the version playing (or loading) now.
    var currentProvider: DebridProvider { DebridProvider.of(link: currentSource.restrictedLink) }

    /// The current source's provider is down — load the best source from a DIFFERENT provider, once
    /// per load.
    ///
    /// The candidate is the first version after the current one in `sources` (already ranked) from
    /// another provider, wrapping round to the ones before it. The resume point carries over: a
    /// load that never played re-resolves it exactly as the first did, and one that did play
    /// reopens at the playhead (`reopenAt`).
    ///
    /// - Returns: false — and the caller shows its normal error — when there is no such version,
    ///   a failover already happened for this load, or the viewer is leaving.
    @discardableResult
    func failOverToOtherProvider() -> Bool {
        guard !failoverUsed, !isTornDown, !isClosing, let candidate = failoverCandidate else { return false }
        let from = currentProvider
        let to = DebridProvider.of(link: sources[candidate].restrictedLink)
        failoverUsed = true
        // Mid-film the place to come back to is the playhead, not whatever the store last heard.
        if reopenAt == nil, playheadSettled, hasRenderedFrame, position > 0 { reopenAt = position }
        engine.note("failover: \(from.displayName) unavailable, loading the \(to.displayName) version")
        // The failed load's watchdog must not call the new version a failure while it is still
        // resolving its link — the new load arms its own once `engine.load` is issued.
        loadWatchdog?.cancel()
        loadWatchdog = nil
        sourceIndex = candidate
        // As `tryAnotherVersion` does: the new version's open gets its own recovery.
        silentRecoveryArmed = true
        automaticReopens = []
        interruptedAt = nil
        reload()
        failoverNoticeTask?.cancel()
        failoverNoticeTask = nil
        failoverNotice = "\(from.displayName) isn't responding — playing from \(to.displayName)"
        return true
    }

    /// The version a failover would load: the first after the current one in `sources` (already
    /// ranked) from another provider, wrapping round to the ones before it. Nil when every version
    /// is on the current provider.
    var failoverCandidate: Int? {
        let count = sources.count
        guard count > 1, sourceIndex < count else { return nil }
        let from = currentProvider
        return (1..<count).lazy
            .map { (self.sourceIndex + $0) % count }
            .first { DebridProvider.of(link: self.sources[$0].restrictedLink) != from }
    }

    /// The viewer asked again, or a new file is coming: a fresh load with its own failover, and no
    /// notice about the last one.
    func resetFailover() {
        failoverUsed = false
        clearFailoverNotice()
    }

    func clearFailoverNotice() {
        failoverNoticeTask?.cancel()
        failoverNoticeTask = nil
        failoverNotice = nil
    }

    /// The failed-over version is on screen: let the notice be read, then go.
    func scheduleFailoverNoticeClear() {
        guard failoverNotice != nil, failoverNoticeTask == nil else { return }
        let seconds = failoverNoticeSeconds
        failoverNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.failoverNotice = nil
            self.failoverNoticeTask = nil
        }
    }
}
