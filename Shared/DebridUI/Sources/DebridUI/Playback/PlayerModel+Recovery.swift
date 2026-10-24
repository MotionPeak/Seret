import Foundation
import DebridCore

/// Failures the viewer should never have to see: the ones the app can recover from by itself.
///
/// Measured on the Apple TV (QA sweep 2026-10-20, §2b): 5 of 26 opens — 19% — ended on
/// "Playback failed.", every one the stream proxy's socket reclaimed while the app sat idle. The
/// proxy now re-listens when it finds its socket dead, but an open that already failed still put
/// the error up when one more try, on a fresh socket and a fresh link, would simply have played.
/// And nothing in front of the load watchdog had a deadline: an RD `unrestrict` that hung kept the
/// spinner up for the watchdog's full 30 s, and one that failed once — a POST, which URLSession
/// never retries, typically -1005 straight after a wake — was "the link could not be opened".
extension PlayerModel {

    // MARK: - One silent reopen

    /// Reopen once — on a fresh socket and a fresh link — instead of showing `.failed`.
    ///
    /// One per failure: armed again only once this media really plays — a tick that advances a
    /// settled playhead (`tick`) — or the viewer asks again (`retry`, `tryAnotherVersion`), so a
    /// stream that keeps failing reaches the error screen after exactly one more try. Not on
    /// libvlc's `.playing`/`.paused`: those come before any frame, and re-arming there let a
    /// stream that opened and failed reopen forever, an RD unrestrict and a libvlc open each
    /// time. A refusal from RD is final and skips it. Mid-film the reopen resumes at the
    /// playhead, and a second failure within 30 s of the same place is shown — a file that
    /// cannot get past a point must not loop. And whatever asks, no more than
    /// `maxAutomaticReopens` a minute (`claimAutomaticReopen`).
    ///
    /// Synchronous on purpose: it disowns the dying media at once (`engineHoldsCurrentMedia`), so
    /// the `.ended` libvlc sends after an error cannot be taken for this media's end meanwhile.
    ///
    /// - Returns: true when a recovery is under way and the caller must not show the failure.
    @discardableResult
    func beginSilentRecovery() -> Bool {
        guard !isTornDown, silentRecoveryArmed, !phase.isFailed else { return false }
        let playhead: Double? = hasRenderedFrame && playheadSettled && position > 0 ? position : nil
        // A reopen that failed before its playhead settled is still at the place it reopened at.
        let place = playhead ?? reopenAt
        if let place, let last = interruptedAt, abs(place - last) <= 30 { return false }
        guard claimAutomaticReopen() else { return false }
        silentRecoveryArmed = false
        engineHoldsCurrentMedia = false        // the failing media's trailing events are not ours
        isBuffering = true
        // The failed load's watchdog must not call the reopen a failure before it has begun.
        loadWatchdog?.cancel()
        loadWatchdog = nil
        let generation = mediaGeneration
        engine.note("recover: reopening silently" + (place.map { " at \(Int($0))s" } ?? " (open)"))
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            // RD saying no is final: a reopen would only ask again.
            if let refusal = await self.streamRefusal() {
                guard self.mediaGeneration == generation, !self.isTornDown else { return }
                self.phase = .failed(refusal)
                return
            }
            guard self.mediaGeneration == generation, !self.isTornDown else { return }
            if let place {
                self.interruptedAt = place
                await self.recordCurrentProgress()
                guard self.mediaGeneration == generation, !self.isTornDown else { return }
                self.reopenAt = place
            }
            self.reload()
        }
        return true
    }

    /// Take one of the automatic reopens this minute allows; false when they are spent.
    ///
    /// The backstop under every automatic reopen: each costs an RD unrestrict, a stream session
    /// and a libvlc open, and a loop of them gets the account throttled by RD. The viewer asking
    /// again (`retry`, `tryAnotherVersion`) or a new episode starts the count afresh.
    func claimAutomaticReopen() -> Bool {
        let now = ContinuousClock.now
        automaticReopens.removeAll { $0.duration(to: now) > automaticReopenWindow }
        guard automaticReopens.count < maxAutomaticReopens else {
            engine.note("recover: \(maxAutomaticReopens) reopens within \(automaticReopenWindow), "
                        + "showing the failure")
            return false
        }
        automaticReopens.append(now)
        return true
    }

    /// Show a failure — in the provider's terms when the stream cache knows why. A reopen that
    /// failed because RD is down said "Playback failed." or "the link may have expired", when the
    /// true answer — and the useful one, since Retry is the next step — is that RD isn't
    /// responding.
    ///
    /// And when the cache says the provider is failing for now, the other provider's version
    /// instead, when the title has one (`failOverToOtherProvider`). This is where a cold open
    /// during an outage — the open and its silent reopen both refused by a 503 — ends up.
    ///
    /// When that is still possible — a cache to ask, another provider's version, no failover yet —
    /// the failure is held, not published, until the cache answers: a `.failed` pulled back a
    /// moment later still flashed the error and, on tvOS, moved focus to Retry. Held as
    /// `beginSilentRecovery` holds a reopen: the dying media's trailing events are disowned and the
    /// viewer sees a wait.
    func fail(_ message: String) {
        let provider = currentProvider
        let generation = mediaGeneration
        if !failoverUsed, streamHandle != nil, failoverCandidate != nil, !phase.isFailed {
            engineHoldsCurrentMedia = false
            isBuffering = true
            failureWordingTask = Task { [weak self] in
                guard let self else { return }
                let failure = await self.streamFailure()
                guard self.mediaGeneration == generation, !self.isTornDown, !self.phase.isFailed else { return }
                if case .unavailable? = failure, self.failOverToOtherProvider() { return }
                self.phase = .failed(failure.map { Self.message(for: $0, provider: provider) } ?? message)
                self.isBuffering = false
            }
            return
        }
        phase = .failed(message)
        isBuffering = false     // it is not waiting on frames; it is over
        guard streamHandle != nil else { return }
        failureWordingTask = Task { [weak self] in
            guard let self, let failure = await self.streamFailure() else { return }
            guard self.mediaGeneration == generation, self.phase == .failed(message) else { return }
            if case .unavailable = failure, self.failOverToOtherProvider() { return }
            self.phase = .failed(Self.message(for: failure, provider: provider))
        }
    }

    static func message(for failure: UpstreamFailure, provider: DebridProvider) -> String {
        switch failure {
        case .refused(let refusal): return refusalMessage(refusal, provider: provider)
        case .unavailable: return unreachableMessage(provider)
        }
    }

    // MARK: - Unrestrict with a deadline and retries

    /// `unrestrict` for a load: a deadline on every attempt, and up to `unrestrictRetryDelays`
    /// retries for the failures that are RD or the network failing for now — all inside
    /// `unrestrictBudget`, so the whole pre-load phase is bounded. RD's own "no" is not retried.
    func unrestrictForLoad(_ link: String) async throws -> URL {
        let clock = ContinuousClock()
        let started = clock.now
        func elapsed() -> Double {
            let d = started.duration(to: clock.now)
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        var retries = 0
        while true {
            do {
                let remaining = unrestrictBudget - elapsed()
                return try await withDeadline(max(0.5, min(unrestrictAttemptTimeout, remaining))) {
                    [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.unrestrict(link)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                guard retries < unrestrictRetryDelays.count, Self.isTransient(error) else { throw error }
                let delay = unrestrictRetryDelays[retries]
                guard elapsed() + delay < unrestrictBudget else { throw error }
                retries += 1
                engine.note("unrestrict failed (\(Self.brief(error))), retry \(retries) in \(delay)s")
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// RD or the network failing for now — worth asking again — as opposed to RD's answer.
    static func isTransient(_ error: Error) -> Bool {
        switch error {
        case is LoadStepTimeout:
            return true
        case let error as HTTPError:
            switch error {
            case .transport: return true
            case .status(let code, _): return code == 408 || code == 429 || (500...599).contains(code)
            case .decoding: return false
            }
        case let error as URLError:
            return ![.badURL, .unsupportedURL, .cancelled, .userAuthenticationRequired].contains(error.code)
        default:
            return false
        }
    }

    /// For the log: never the URL (an unrestricted RD link carries its token).
    static func brief(_ error: Error) -> String {
        switch error {
        case is LoadStepTimeout: return "timed out"
        case let error as HTTPError:
            if case .status(let code, _) = error { return "HTTP \(code)" }
            return "transport"
        case let error as URLError: return "URLError \(error.code.rawValue)"
        default: return String(describing: type(of: error))
        }
    }

    /// Run `operation`, giving up after `seconds`.
    ///
    /// Not a task group: the operation may await something that ignores cancellation — the link
    /// cache awaits an in-flight prefetch's `Task.value`, which does — and a group would wait for
    /// it anyway. Here the deadline answers on its own and the operation is merely cancelled.
    func withDeadline<T: Sendable>(_ seconds: Double,
                                   _ operation: @escaping @MainActor @Sendable () async throws -> T)
        async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                gate.install(continuation)
                gate.track(Task { @MainActor in
                    do { gate.finish(.success(try await operation())) } catch { gate.finish(.failure(error)) }
                })
                gate.track(Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    gate.finish(.failure(LoadStepTimeout()))
                })
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// A step of the load that ran out of time.
struct LoadStepTimeout: Error {}

/// The first of the operation, the deadline and a cancellation to answer wins; the rest are
/// dropped, and both tasks are cancelled once one has. `@unchecked` because every field is behind
/// the lock.
private final class DeadlineGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var early: Result<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var done = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let early {
            lock.unlock()
            continuation.resume(with: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        let cancelNow = done
        if !cancelNow { tasks.append(task) }
        lock.unlock()
        if cancelNow { task.cancel() }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { early = result }
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        continuation?.resume(with: result)
        for task in tasks { task.cancel() }
    }
}
