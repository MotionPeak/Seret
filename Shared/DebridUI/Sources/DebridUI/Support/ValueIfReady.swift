import Foundation

/// The value of `task` if it finishes within `limit`, nil otherwise — WITHOUT cancelling it, so a
/// late value still reaches whoever else awaits the task.
///
/// A task group cannot do this: it waits for every child before returning, so the slow branch would
/// hold the answer hostage however early the timer fired.
func valueIfReady<T: Sendable>(of task: Task<T, Never>, within limit: Duration) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = ResumeOnce()
        let timer = Task {
            try? await Task.sleep(for: limit)
            if gate.claim() { continuation.resume(returning: nil) }
        }
        Task {
            let value = await task.value
            if gate.claim() {
                timer.cancel()
                continuation.resume(returning: value)
            }
        }
    }
}

/// Lets exactly one of two racers resume a continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
