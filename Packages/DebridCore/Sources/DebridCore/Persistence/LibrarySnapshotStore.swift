import Foundation

/// Persists the library cache to a single JSON file in `directory`. Reads degrade to `nil`
/// (missing / unreadable / decode failure / schema mismatch) so the caller rebuilds from RD —
/// a bad cache must never crash or surface an error.
public struct LibrarySnapshotStore: Sendable {
    private let directory: URL
    private var fileURL: URL { directory.appending(path: "library.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)   // write-temp-then-rename
    }

    public func load() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              snapshot.schemaVersion == LibrarySnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
