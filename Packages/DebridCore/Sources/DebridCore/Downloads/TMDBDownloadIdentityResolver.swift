import Foundation

/// Identifies a torrent from its release name via TMDB, caching by infohash.
///
/// The cache stores misses as well as hits. The monitor polls every few seconds, so an
/// unmatchable release name would otherwise re-query TMDB forever and never succeed.
public actor TMDBDownloadIdentityResolver: DownloadIdentityResolving {
    private let search: any DownloadTitleSearching
    private let parser = FilenameParser()
    /// `nil` value = resolved to nothing. Distinguished from "not yet attempted" by key presence.
    private var cache: [String: DownloadIdentity?] = [:]

    public init(search: any DownloadTitleSearching) {
        self.search = search
    }

    public func identity(filename: String, infoHash: String) async -> DownloadIdentity? {
        if let cached = cache[infoHash] { return cached }   // one unwrap: a stored miss returns nil
        let resolved = await resolve(parser.parse(filename))
        cache[infoHash] = resolved
        return resolved
    }

    private func resolve(_ parsed: ParsedRelease) async -> DownloadIdentity? {
        let name = parsed.title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        if parsed.isTV {
            let hits = (try? await search.searchTV(query: name, firstAirYear: parsed.year)) ?? []
            guard let hit = hits.first else { return nil }
            let key: String
            if let season = parsed.season, let episode = parsed.episode {
                key = DownloadKey.episode(showTmdbID: hit.id, season: season, number: episode)
            } else if let season = parsed.season {
                key = DownloadKey.season(showTmdbID: hit.id, season: season)
            } else {
                return nil   // an episode number with no season is not an addressable unit
            }
            return DownloadIdentity(contentKey: key, tmdbID: hit.id, kind: .show,
                                    title: hit.name ?? name, posterPath: hit.posterPath)
        }

        let hits = (try? await search.searchMovie(query: name, year: parsed.year)) ?? []
        guard let hit = hits.first else { return nil }
        return DownloadIdentity(contentKey: DownloadKey.movie(tmdbID: hit.id), tmdbID: hit.id,
                                kind: .movie, title: hit.title ?? name,
                                posterPath: hit.posterPath)
    }
}
