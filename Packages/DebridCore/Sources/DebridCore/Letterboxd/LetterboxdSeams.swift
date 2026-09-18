import Foundation

/// Reads a member's public profile.
///
/// A seam rather than the concrete `LetterboxdProfileReader` so the importer can be tested with an
/// in-memory fake. That is not only convenience: the importer needs SwiftData, and a SwiftData
/// suite must nest under `SwiftDataSuite` while anything using `MockURLProtocol` must nest under
/// `MockTests`. A test cannot be under both, and one that tries races on the shared mock handler
/// and breaks unrelated suites. Depending on a seam removes the dilemma.
public protocol LetterboxdProfileReading: Sendable {
    func films() async throws -> [LetterboxdEntry]
    func watchlist() async throws -> [LetterboxdEntry]
}

/// Turns a TMDB id into a Letterboxd slug. Throws `LetterboxdError.filmNotFound` when there is none.
public protocol LetterboxdFilmResolving: Sendable {
    func slug(forTMDB id: Int) async throws -> String
}

extension LetterboxdProfileReader: LetterboxdProfileReading {}
extension LetterboxdFilmResolver: LetterboxdFilmResolving {}
