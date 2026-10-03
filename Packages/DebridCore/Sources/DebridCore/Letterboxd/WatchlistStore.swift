import Foundation

/// The watchlist mirror on disk.
///
/// A JSON file, not SwiftData and not CloudKit: this is a rebuildable copy of someone else's data,
/// so a schema migration would be cost without benefit and every device can sync for itself.
/// Losing the file costs one sync.
///
/// Every failure degrades to empty — a screen that cannot read its cache should sync, not crash.
public struct WatchlistStore: Sendable {
    private let fileURL: URL?

    public init(fileURL: URL?) { self.fileURL = fileURL }

    /// Located through `WritableStorage`, which proves the directory by creating it — tvOS has no
    /// `Application Support` and assuming otherwise has failed silently on a real device before.
    public static func defaultURL() -> URL? {
        WritableStorage.file(named: "letterboxd-watchlist.json")
    }

    /// A partner's watchlist lives in its own file, named for the username — so changing who the
    /// partner is never shows the previous person's list under the new name, even for a moment.
    public static func partnerURL(username: String) -> URL? {
        WritableStorage.file(named: partnerFileName(username: username))
    }

    /// Lower-cased, and anything outside `[a-z0-9_-]` replaced, so a username cannot name a path.
    static func partnerFileName(username: String) -> String {
        let safe = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" }
        return "letterboxd-watchlist-partner-\(String(safe)).json"
    }

    public func load() -> [WatchlistEntry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WatchlistEntry].self, from: data)
        else { return [] }
        return decoded.sorted { $0.position < $1.position }
    }

    public func save(_ entries: [WatchlistEntry]) {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
