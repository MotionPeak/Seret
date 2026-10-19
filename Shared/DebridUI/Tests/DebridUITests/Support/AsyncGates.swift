import Foundation
import Testing

/// A one-shot latch for deterministic async tests: waiters suspend until `open()`, and a waiter
/// arriving after it opened returns at once. No clocks anywhere.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let w = waiters; waiters = []
        w.forEach { $0.resume() }
    }
}

/// Counts events and lets a test suspend until at least `n` have happened.
actor AsyncCounter {
    private(set) var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func increment() {
        count += 1
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }
    func wait(atLeast n: Int) async {
        if count >= n { return }
        await withCheckedContinuation { waiters.append((n, $0)) }
    }
}

/// Lets queued main-actor work run. Bounded; never sleeps.
@MainActor func settle(_ passes: Int = 30) async {
    for _ in 0..<passes { await Task.yield() }
}

/// Waits for `condition` by yielding in a loop - a positive check waits for the thing to happen
/// instead of guessing how many yields it takes, so a starved CPU only slows it down. Bounded so a
/// real failure still ends; records an issue when the cap is hit.
@MainActor func until(_ message: Comment = "condition never became true", cap: Int = 10_000,
                      sourceLocation: SourceLocation = #_sourceLocation,
                      _ condition: () -> Bool) async {
    for _ in 0..<cap {
        if condition() { return }
        await Task.yield()
    }
    Issue.record(message, sourceLocation: sourceLocation)
}
