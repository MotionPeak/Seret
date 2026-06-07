import Foundation
import SwiftData

/// A title the user asked RD to download. CloudKit-ready (all defaulted, no unique constraint).
/// `torrentID` is the dedupe key (enforced in `DownloadsStore`, not by SwiftData).
@Model
public final class DownloadRequest {
    public var torrentID: String = ""
    public var tmdbID: Int = 0
    public var infoHash: String = ""
    public var kindRaw: String = "movie"   // MediaKind.rawValue
    public var title: String = ""
    public var requestedAt: Date = Date(timeIntervalSince1970: 0)

    public init(torrentID: String = "", tmdbID: Int = 0, infoHash: String = "",
                kindRaw: String = "movie", title: String = "",
                requestedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.infoHash = infoHash
        self.kindRaw = kindRaw; self.title = title; self.requestedAt = requestedAt
    }
}

/// A `Sendable` snapshot of a `DownloadRequest` — what the store hands back across the actor boundary.
public struct DownloadRequestData: Sendable, Equatable, Identifiable {
    public let torrentID: String
    public let tmdbID: Int
    public let infoHash: String
    public let kind: MediaKind
    public let title: String
    public let requestedAt: Date

    public var id: String { torrentID }

    public init(torrentID: String, tmdbID: Int, infoHash: String, kind: MediaKind,
                title: String, requestedAt: Date) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.infoHash = infoHash
        self.kind = kind; self.title = title; self.requestedAt = requestedAt
    }

    init(_ m: DownloadRequest) {
        self.init(torrentID: m.torrentID, tmdbID: m.tmdbID, infoHash: m.infoHash,
                  kind: MediaKind(rawValue: m.kindRaw) ?? .movie, title: m.title,
                  requestedAt: m.requestedAt)
    }
}
