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
