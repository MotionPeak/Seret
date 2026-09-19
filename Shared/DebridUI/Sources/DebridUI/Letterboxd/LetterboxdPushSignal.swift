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
    public private(set) var lastLogged: Int?
    /// Changes on every landed entry, including a repeat of the same film.
    public private(set) var event: UUID?

    public init() {}

    public func logged(tmdbID: Int) {
        lastLogged = tmdbID
        event = UUID()
    }
}
