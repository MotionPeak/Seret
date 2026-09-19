import DebridCore
import Foundation

/// What a push failure means to the person reading it, and what they can do about it.
///
/// The raw enum name reaches the settings card otherwise — "notAuthenticated" on a television,
/// which explains nothing and suggests nothing. Caught by screenshotting the card rather than by
/// any test, because every test only ever asserted that a message existed.
extension LetterboxdError {
    var ownerFacingMessage: String {
        switch self {
        case .notAuthenticated:
            return "Letterboxd signed us out — sign in again in the browser on your Synology."
        case .challenged:
            return "Letterboxd is challenging the browser — open it on your Synology and solve it."
        case .filmNotFound:
            return "Letterboxd doesn't have that film, so it was skipped."
        case .profileUnavailable:
            return "That Letterboxd profile is private or gone."
        case .structureChanged:
            return "Letterboxd changed — Seret needs updating before it can write again."
        case .transient(let message):
            return "Couldn't reach Seret on your Synology (\(message))."
        }
    }
}

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
    /// Told only about entries that landed, so a view can confirm one. Optional because the push
    /// works perfectly well with nobody listening.
    private let signal: LetterboxdPushSignal?
    private var lastError: String?
    /// The send in flight, if any. Held so one drain cannot start on top of another, and so a test
    /// can wait for a send it deliberately stalled.
    private var sendTask: Task<Void, Never>?
    /// How long a new diary entry waits for a rating before going out as it stands.
    private let ratingHold: TimeInterval
    /// The entry currently waiting on the viewer. One at a time: you can only finish one film at
    /// a time, and a second one finishing is reason enough to stop waiting on the first.
    private var awaitingRating: (id: UUID, tmdbID: Int, rating: Int?)?
    /// Releases the hold when it runs out. Cancelled when the viewer answers first.
    private var holdTask: Task<Void, Never>?
    /// A drain asked for while one was already running.
    private var drainAgain = false

    public init(outbox: any LetterboxdOutbox,
                relay: any LetterboxdRelaying,
                loggedElsewhere: @escaping @Sendable (Int) -> Bool,
                isEnabled: @escaping @Sendable () -> Bool,
                signal: LetterboxdPushSignal? = nil,
                ratingHold: TimeInterval = 120) {
        self.outbox = outbox
        self.relay = relay
        self.loggedElsewhere = loggedElsewhere
        self.isEnabled = isEnabled
        self.signal = signal
        self.ratingHold = ratingHold
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

        // Held back, so the viewer can put a rating on it while the credits are still rolling.
        // `watchedAt` is stamped now regardless, so a late send still files the entry on the day
        // the film was actually watched.
        let write = LetterboxdWrite(tmdbID: tmdbID, rating: rating, watchedAt: at,
                                    rewatch: rewatch,
                                    notBefore: at.addingTimeInterval(ratingHold))
        // Awaited: the write must be on disk before this returns, or being killed here loses it.
        try? await outbox.enqueue(write)

        if ratingHold > 0 {
            // A second film finishing supersedes the first: its prompt is the one on screen.
            awaitingRating = (write.id, tmdbID, rating)
            let current = rating
            await MainActor.run { signal?.askForRating(tmdbID: tmdbID, current: current) }
            scheduleHoldRelease()
        }

        // NOT awaited. The caller is the 1s playback tick, and sending drives a browser on the
        // Synology — nearly nine seconds, measured. The player allows one save in flight at a
        // time, so waiting here stops position-saving for the whole of it.
        //
        // Still worth starting with a write of our own held back: anything queued EARLIER — a
        // film finished while the Synology was off — is due now and has waited long enough.
        startSend(now: at)
    }

    /// The viewer rated the held film. Writes it onto the entry and sends.
    ///
    /// Named by film rather than taken on trust, because the prompt can be superseded: by the time
    /// a press lands, the entry waiting may be for a different film entirely.
    public func rate(_ value: Int?, forFilm tmdbID: Int) async {
        guard let pending = awaitingRating, pending.tmdbID == tmdbID else { return }
        awaitingRating = nil
        holdTask?.cancel()
        holdTask = nil

        let now = Date()
        try? await outbox.amend(pending.id, rating: value, notBefore: now)
        await MainActor.run { signal?.stopAskingForRating() }
        startSend(now: now)
    }

    /// The viewer dismissed the prompt. Sends the entry exactly as it stands — a film already
    /// rated on the title page keeps that rating, because ignoring a prompt is not an instruction
    /// to erase your own data.
    public func dismissRating(forFilm tmdbID: Int) async {
        guard let pending = awaitingRating, pending.tmdbID == tmdbID else { return }
        await rate(pending.rating, forFilm: tmdbID)
    }

    /// Lets the hold lapse on its own, sending the entry unchanged.
    ///
    /// The entry's `notBefore` is already the deadline, so this only has to take the prompt down
    /// and knock on the drain — the queue was always going to release it.
    private func scheduleHoldRelease() {
        holdTask?.cancel()
        let seconds = ratingHold
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.holdExpired()
        }
    }

    private func holdExpired() async {
        guard awaitingRating != nil else { return }
        awaitingRating = nil
        holdTask = nil
        await MainActor.run { signal?.stopAskingForRating() }
        startSend(now: Date())
    }

    /// Waits for a hold to lapse. For tests that set a short one; nothing in the app waits.
    public func waitForRatingHold() async { await holdTask?.value }

    /// Kicks off a drain unless one is already running. Two concurrent drains would take the same
    /// write off the queue twice and file the film twice.
    ///
    /// A request that arrives while one is running is REMEMBERED rather than dropped. Dropping it
    /// was silent data loss the moment ratings arrived: `recordFinish` starts a drain, the viewer
    /// rates the film a moment later, and the rating's own drain hit this guard and did nothing —
    /// so the entry sat in the queue holding a rating nobody was going to send.
    private func startSend(now: Date) {
        guard sendTask == nil else { drainAgain = true; return }
        sendTask = Task { [weak self] in
            await self?.drain(now: now)
            await self?.sendFinished()
        }
    }

    private func sendFinished() {
        sendTask = nil
        guard drainAgain else { return }
        drainAgain = false
        startSend(now: Date())
    }

    /// Waits for a send already in flight. For tests that stall the relay on purpose; nothing in
    /// the app waits for a send, which is the entire point of the change that introduced this.
    ///
    /// Loops, because finishing one drain can immediately start the follow-up above.
    public func waitForPendingSend() async {
        while let task = sendTask { await task.value }
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
                let tmdbID = write.tmdbID
                await MainActor.run { signal?.logged(tmdbID: tmdbID) }
            } catch let error as LetterboxdError {
                switch error {
                case .filmNotFound, .structureChanged, .profileUnavailable:
                    // Permanent. Retrying cannot help, and leaving it queued would block the films
                    // behind it for as long as the app is installed.
                    lastError = error.ownerFacingMessage
                    try? await outbox.complete(write.id)
                case .notAuthenticated, .challenged:
                    // The browser needs a human. Stop the whole drain rather than marching the rest
                    // of the queue into the same wall and inflating every one of their backoffs.
                    lastError = error.ownerFacingMessage
                    try? await outbox.fail(write.id, error: error.ownerFacingMessage, at: now)
                    return
                case .transient:
                    lastError = error.ownerFacingMessage
                    try? await outbox.fail(write.id, error: error.ownerFacingMessage, at: now)
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
