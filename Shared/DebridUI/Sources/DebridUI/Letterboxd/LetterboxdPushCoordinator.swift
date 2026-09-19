import DebridCore
import Foundation

/// Mirrors finished films onto Letterboxd.
///
/// Local watch state is the truth and Letterboxd is the mirror: a failed write never alters
/// anything here, it waits. The queue lives on this device, because the server that owns the
/// browser keeps no state of its own.
public actor LetterboxdPushCoordinator {
    private let outbox: any LetterboxdOutbox
    private let relay: any LetterboxdRelaying
    private let loggedElsewhere: @Sendable (Int) -> Bool
    private let isEnabled: @Sendable () -> Bool
    private var lastError: String?

    public init(outbox: any LetterboxdOutbox,
                relay: any LetterboxdRelaying,
                loggedElsewhere: @escaping @Sendable (Int) -> Bool,
                isEnabled: @escaping @Sendable () -> Bool) {
        self.outbox = outbox
        self.relay = relay
        self.loggedElsewhere = loggedElsewhere
        self.isEnabled = isEnabled
    }

    /// Called on the unfinished→finished edge, and only there.
    public func recordFinish(contentKey: String, rating: Int?, plays: Int, at: Date) async {
        guard isEnabled() else { return }
        // Letterboxd has no television, and a parsed-title key is not a TMDB id. Neither can ever
        // be written, so neither is queued — a permanent failure in the queue blocks what follows.
        guard let tmdbID = LetterboxdContentKey.tmdbID(fromMovieKey: contentKey) else { return }

        // Either source is enough. The local count cannot know about a film logged there years
        // ago, and the Letterboxd list cannot know about one watched only here.
        let rewatch = plays > 1 || loggedElsewhere(tmdbID)

        let write = LetterboxdWrite(tmdbID: tmdbID, rating: rating, watchedAt: at, rewatch: rewatch)
        try? await outbox.enqueue(write)
        await drain(now: at)
    }

    /// Sends everything that is due. Safe to call often — on enqueue, on foreground, on a refresh.
    public func drain(now: Date = Date()) async {
        guard isEnabled() else { return }
        guard let due = try? await outbox.due(at: now) else { return }

        for write in due {
            do {
                try await relay.send(write)
                try? await outbox.complete(write.id)
                lastError = nil
            } catch let error as LetterboxdError {
                switch error {
                case .filmNotFound, .structureChanged, .profileUnavailable:
                    // Permanent. Retrying cannot help, and leaving it queued would block the films
                    // behind it for as long as the app is installed.
                    lastError = "\(error)"
                    try? await outbox.complete(write.id)
                case .notAuthenticated, .challenged:
                    // The browser needs a human. Stop the whole drain rather than marching the rest
                    // of the queue into the same wall and inflating every one of their backoffs.
                    lastError = "\(error)"
                    try? await outbox.fail(write.id, error: "\(error)", at: now)
                    return
                case .transient(let message):
                    lastError = message
                    try? await outbox.fail(write.id, error: message, at: now)
                }
            } catch {
                let message = String(describing: error)
                lastError = message
                try? await outbox.fail(write.id, error: message, at: now)
            }
        }
    }

    /// For the settings row. A queue stuck behind an expired browser session has to be visible.
    public func status() async -> (pending: Int, lastError: String?) {
        ((try? await outbox.all().count) ?? 0, lastError)
    }
}
