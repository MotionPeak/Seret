import DebridCore
import Foundation

/// Answers the rating prompt that appears when a film's credits roll.
///
/// Two destinations, and they are not interchangeable. The local store is the source of truth —
/// it is what the title page shows, and it survives Letterboxd being unreachable, unconfigured or
/// gone. The held diary entry is the mirror. Local is written first for that reason.
///
/// Small and injectable rather than a method on `AppSession`, so the one rule worth protecting can
/// actually be tested: dismissing the prompt writes NOTHING locally.
@MainActor
public struct FinishedFilmRating {
    private let local: (any WatchRatingProviding)?
    private let push: LetterboxdPushCoordinator?

    public init(local: (any WatchRatingProviding)?, push: LetterboxdPushCoordinator?) {
        self.local = local
        self.push = push
    }

    /// The viewer picked a rating — or cleared one, which is just as deliberate an answer.
    public func rate(_ value: Int?, contentKey: String, tmdbID: Int) async {
        await local?.setRating(value, forContentKey: contentKey)
        await push?.rate(value, forFilm: tmdbID)
    }

    /// The viewer dismissed the prompt, or it lapsed. The entry goes out as it stands.
    ///
    /// 🚨 Nothing is written locally. Writing nil here would clear a rating the film already had
    /// from the title page — destroying the viewer's own data because they ignored a prompt.
    public func dismiss(tmdbID: Int) async {
        await push?.dismissRating(forFilm: tmdbID)
    }
}
