#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed registry of in-progress download requests. `@ModelActor` isolates its
/// `ModelContext`, so it is safe from any task. Returns `Sendable` `DownloadRequestData` values.
@ModelActor
public actor DownloadsStore {
    /// Insert-or-update the row for `data.torrentID` (CloudKit forbids a unique constraint, so
    /// we dedupe here, mirroring `WatchProgressStore`).
    public func upsert(_ data: DownloadRequestData) throws {
        let row = try fetchOne(torrentID: data.torrentID) ?? {
            let r = DownloadRequest(); modelContext.insert(r); return r
        }()
        row.torrentID = data.torrentID
        row.tmdbID = data.tmdbID
        row.infoHash = data.infoHash
        row.kindRaw = data.kind.rawValue
        row.title = data.title
        row.posterPath = data.posterPath
        row.requestedAt = data.requestedAt
        try modelContext.save()
    }

    public func all() throws -> [DownloadRequestData] {
        try modelContext.fetch(FetchDescriptor<DownloadRequest>(
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)])).map(DownloadRequestData.init)
    }

    public func find(tmdbID: Int) throws -> DownloadRequestData? {
        var d = FetchDescriptor<DownloadRequest>(predicate: #Predicate { $0.tmdbID == tmdbID })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first.map(DownloadRequestData.init)
    }

    public func delete(torrentID: String) throws {
        guard let row = try fetchOne(torrentID: torrentID) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    private func fetchOne(torrentID key: String) throws -> DownloadRequest? {
        var d = FetchDescriptor<DownloadRequest>(predicate: #Predicate { $0.torrentID == key })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
#endif
