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
