import DebridCore

/// Resolves a YouTube trailer key for a title. Thin seam over `TMDBClient` `/videos`.
public protocol TrailerProviding: Sendable {
    /// The YouTube video id of the title's trailer (or teaser), or nil if none / on error.
    func trailerKey(tmdbID: Int, kind: MediaKind) async -> String?
}

public struct TMDBTrailerService: TrailerProviding {
    let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }
    public func trailerKey(tmdbID: Int, kind: MediaKind) async -> String? {
        let videos = try? await (kind == .movie ? client.movieVideos(id: tmdbID)
                                                 : client.tvVideos(id: tmdbID))
        return videos?.firstYouTubeTrailer?.key
    }
}
