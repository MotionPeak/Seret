import Foundation
import Observation

/// Announces that a diary entry actually landed, so a view can say so.
///
/// It carries a TMDB id rather than a title because that is all the push knows — the player knows
/// which film it is playing and can match. And it carries an `event` token as well, because a
/// rewatch logs the same film twice and a view watching the id alone would see no change.
///
/// Nothing is announced for a failure. A dead browser is not actionable while a film is playing,
/// Settings already carries it, and interrupting the film to say so is worse than silence.
@MainActor
@Observable
public final class LetterboxdPushSignal {
    /// A diary entry waiting on the viewer before it is sent.
    public struct RatingPrompt: Equatable, Sendable {
        public let tmdbID: Int
        /// What the film is already rated, so a rewatch starts from that rather than blank.
        public let current: Int?
    }

    public private(set) var lastLogged: Int?
    /// Changes on every landed entry, including a repeat of the same film.
    public private(set) var event: UUID?
    /// Set while a diary entry is held back for a rating, and cleared the moment it is answered,
    /// dismissed, or the hold runs out. A view shows the stars for exactly as long as this is set.
    public private(set) var ratingPrompt: RatingPrompt?

    public init() {}

    public func logged(tmdbID: Int) {
        lastLogged = tmdbID
        event = UUID()
    }

    public func askForRating(tmdbID: Int, current: Int?) {
        ratingPrompt = RatingPrompt(tmdbID: tmdbID, current: current)
    }

    public func stopAskingForRating() { ratingPrompt = nil }
}
