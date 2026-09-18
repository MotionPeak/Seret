import Foundation

public enum LetterboxdError: Error, Equatable, Sendable {
    /// A 200 page parsed to zero entries. Loud on purpose: a silent scraper that returns nothing
    /// looks exactly like an empty account and would stop working forever without anyone noticing.
    case structureChanged
    /// Profile private, renamed or gone.
    case profileUnavailable
    /// No Letterboxd film corresponds to that TMDB id.
    case filmNotFound
    /// The session cookie is dead or was rejected.
    case notAuthenticated
    /// Cloudflare interposed a challenge.
    case challenged
    case transient(String)
}
