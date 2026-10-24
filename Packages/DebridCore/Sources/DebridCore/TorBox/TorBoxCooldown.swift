import Foundation

/// The window after a TorBox 429 in which no request may go out.
///
/// TorBox locks a key out for about five minutes after a 429, and every request inside that window
/// extends it. With Real-Debrid still answering, the composite never throws, so the download
/// store's backoff never engages and `mylist` was polled every 5 s straight through the lockout.
/// Now the client itself refuses — `.rateLimited`, no request — until the window passes.
///
/// A reference type, so every copy of a `TorBoxClient` shares one window. `@unchecked Sendable`
/// because the one mutable field is behind the lock.
public final class TorBoxCooldown: @unchecked Sendable {
    /// TorBox's documented lockout, used when the 429 named no `Retry-After`.
    public static let defaultLockout: TimeInterval = 300

    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var lockedUntil: Date?

    /// - Parameter now: the clock; injected so tests can step through the window.
    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Throws `.rateLimited` with the seconds left while the window is open.
    func check() throws {
        let current = now()
        let remaining: TimeInterval? = lock.withLock {
            guard let until = lockedUntil else { return nil }
            if until <= current { lockedUntil = nil; return nil }
            return until.timeIntervalSince(current)
        }
        if let remaining { throw TorBoxError.rateLimited(retryAfter: Int(remaining.rounded(.up))) }
    }

    /// Opens (or extends) the window after a 429.
    func lockOut(retryAfter: Int?) {
        let seconds = retryAfter.map(TimeInterval.init) ?? Self.defaultLockout
        let until = now().addingTimeInterval(seconds)
        lock.withLock {
            if let current = lockedUntil, current >= until { return }
            lockedUntil = until
        }
    }
}
