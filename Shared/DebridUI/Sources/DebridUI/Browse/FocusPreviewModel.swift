import Foundation
import Observation

/// Debounces the focus-driven preview header. Gliding along a rail moves focus across many tiles a
/// second; only the one focus settles on should re-render the header, so `focus(_:)` waits out
/// `debounce` with no newer focus before publishing.
@MainActor
@Observable
public final class FocusPreviewModel {
    public private(set) var shown: PreviewSubject?

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleeper: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Bumped on every focus / immediate show, so a sleep that outlives its cancellation (an
    /// injected sleeper needn't honour it) still can't publish a stale subject.
    @ObservationIgnored private var generation: UInt64 = 0

    public init(debounce: Duration = .milliseconds(150),
                sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.debounce = debounce
        self.sleeper = sleeper
    }

    /// Publishes `subject` after `debounce` with no newer focus. Focusing what is already shown
    /// just drops any pending change (glided off it and straight back).
    public func focus(_ subject: PreviewSubject) {
        cancelPending()
        guard subject != shown else { return }
        let generation = generation
        let (debounce, sleeper) = (debounce, sleeper)
        pending = Task { [weak self] in
            do { try await sleeper(debounce) } catch { return }
            guard let self, self.generation == generation else { return }
            self.shown = subject
            self.pending = nil
        }
    }

    /// Publishes `subject` now and drops any pending focus (first appearance, a page change).
    public func showImmediately(_ subject: PreviewSubject) {
        cancelPending()
        shown = subject
    }

    /// Shows nothing and drops any pending focus — what is on screen no longer describes anything
    /// on the page (a genre grid swapped for another, before its titles land).
    public func clear() {
        cancelPending()
        shown = nil
    }

    private func cancelPending() {
        generation &+= 1
        pending?.cancel()
        pending = nil
    }
}
