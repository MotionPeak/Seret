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

/// Reads and writes the viewer's own rating for a title.
///
/// A seam because `LocalWatchStore` only exists where SwiftData does, and this package is compiled
/// for Linux by `SeretServer`. The profile is named explicitly on every call: the import refuses to
/// run until it is known, and a store that resolves the profile itself would reintroduce the second
/// source of truth that produced orphaned rows.
public protocol LetterboxdRatingStoring: Sendable {
    func rating(forContentKey key: String, profileID: String) async throws -> Int?
    func setRating(_ value: Int?, contentKey: String, profileID: String) async throws
}

extension LetterboxdProfileReader: LetterboxdProfileReading {}
extension LetterboxdFilmResolver: LetterboxdFilmResolving {}

#if canImport(SwiftData)
extension LocalWatchStore: LetterboxdRatingStoring {
    /// The stored method carries an `at:` for tests to pin time with; the seam does not need it.
    public func setRating(_ value: Int?, contentKey: String, profileID: String) async throws {
        try setRating(value, contentKey: contentKey, profileID: profileID, at: Date())
    }
}
#endif
