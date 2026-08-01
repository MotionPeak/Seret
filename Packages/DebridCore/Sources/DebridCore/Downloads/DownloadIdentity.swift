import Foundation

/// Who a downloading torrent belongs to: the content key it files under, plus enough metadata to
/// render a tile without consulting the library (a downloading title is not in the library — RD
/// returns no links until it finishes, so `LibraryBuilder` cannot build sources for it).
public struct DownloadIdentity: Sendable, Equatable {
    public let contentKey: String
    public let tmdbID: Int
    public let kind: MediaKind
    public let title: String
    public let posterPath: String?

    public init(contentKey: String, tmdbID: Int, kind: MediaKind, title: String,
                posterPath: String? = nil) {
        self.contentKey = contentKey; self.tmdbID = tmdbID; self.kind = kind
        self.title = title; self.posterPath = posterPath
    }
}

/// Resolves a torrent Seret did not start — one added on another device, in DMM, or RD's web UI.
public protocol DownloadIdentityResolving: Sendable {
    func identity(filename: String, infoHash: String) async -> DownloadIdentity?
}

/// The TMDB searches identity resolution needs. Narrow on purpose, so the resolver is testable
/// without HTTP. `TMDBClient` conforms as-is.
public protocol DownloadTitleSearching: Sendable {
    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult]
    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult]
}

extension TMDBClient: DownloadTitleSearching {}
