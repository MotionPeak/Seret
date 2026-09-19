import Foundation

/// The TMDB ids of films already logged on Letterboxd, as of the last import.
///
/// This is the half of the rewatch rule Seret cannot know on its own: a film watched years ago and
/// logged there, then watched again here, is a rewatch that a local play count has no way to see.
/// Without it the diary would show a first viewing that contradicts an older entry.
///
/// An empty set means "never synced", not "never watched" — the rule falls back to `plays > 1`.
public struct LetterboxdLoggedFilms: Sendable {
    private let fileURL: URL?

    public init(fileURL: URL?) { self.fileURL = fileURL }

    /// Located through `WritableStorage`, which proves the directory by creating it — tvOS has no
    /// `Application Support` and assuming otherwise has failed silently on a real device before.
    public static func defaultURL() -> URL? {
        WritableStorage.file(named: "letterboxd-logged-films.json")
    }

    public func load() -> Set<Int> {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(ids)
    }

    /// Sorted on the way out purely so the file is readable and diffable by a human debugging it.
    public func save(_ ids: Set<Int>) {
        guard let fileURL, let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func contains(tmdbID: Int) -> Bool { load().contains(tmdbID) }
}
