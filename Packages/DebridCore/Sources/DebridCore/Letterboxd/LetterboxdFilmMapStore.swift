import Foundation

/// Keeps the TMDB-id-to-slug map across launches.
///
/// Without it every launch re-resolves every film over the network, which is the single most
/// expensive part of an import. Slugs are stable on Letterboxd, so entries never expire.
///
/// Every failure degrades to "empty" rather than throwing: a lost cache costs time, and an import
/// that refuses to run because its cache is unreadable costs the feature.
public struct LetterboxdFilmMapStore: Sendable {
    private let fileURL: URL?

    public init(fileURL: URL?) { self.fileURL = fileURL }

    /// Located through `WritableStorage`, which proves the directory by creating it — tvOS has no
    /// `Application Support` and assuming otherwise has failed silently on a real device before.
    public static func defaultURL() -> URL? {
        WritableStorage.file(named: "letterboxd-film-map.json")
    }

    public func load() -> [Int: String] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded.reduce(into: [Int: String]()) { out, pair in
            if let id = Int(pair.key) { out[id] = pair.value }
        }
    }

    public func save(_ slugs: [Int: String]) {
        guard let fileURL else { return }
        // JSON object keys must be strings, so the ids are written as such and parsed back on load.
        let encodable = slugs.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
