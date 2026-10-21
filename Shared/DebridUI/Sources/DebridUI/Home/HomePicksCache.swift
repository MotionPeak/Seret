import Foundation
import DebridCore

/// The day's "Picked for right now" list, as it was computed.
///
/// The picks are stored UNFILTERED by local watch state: a film finished after the list was made
/// is dropped when the list is shown, not when it is saved, so the file never has to be rewritten
/// to stay right.
public struct HomePicksSnapshot: Codable, Sendable, Equatable {
    /// The local calendar day it was computed on, `yyyy-MM-dd` — `HomePicksStore.day(of:)`.
    public let day: String
    public let picks: [WatchlistPick]
    /// The Letterboxd account whose diary the picks follow, so a list made for another account is
    /// never shown and is recomputed at once. Nil in a file written before this existed.
    public let username: String?

    public init(day: String, picks: [WatchlistPick], username: String? = nil) {
        self.day = day
        self.picks = picks
        self.username = username
    }

    private enum CodingKeys: String, CodingKey { case day, picks, username }

    /// Lenient about fields added later: an older file that failed to decode would empty the row
    /// until the next refresh.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        picks = try c.decode([WatchlistPick].self, forKey: .picks)
        username = try c.decodeIfPresent(String.self, forKey: .username)
    }
}

/// One JSON file holding the last `HomePicksSnapshot`.
///
/// An actor so a write never interleaves with a read. Every failure degrades to "no cache": a
/// missing or unreadable file means the row waits for the next refresh, never an error on Home.
public actor HomePicksCache {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func read() -> HomePicksSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(HomePicksSnapshot.self, from: data)
    }

    public func write(_ snapshot: HomePicksSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
