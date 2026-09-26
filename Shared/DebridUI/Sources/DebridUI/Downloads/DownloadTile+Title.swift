import DebridCore

extension DownloadTile {
    /// The page a download opens: the library item once it has landed (same tmdbID AND kind —
    /// a movie and a show can share a TMDB id, and the library's index is kind-blind), else a
    /// placeholder built from the tile itself. `nil` for a download TMDB never identified
    /// (`tmdbID <= 0`) — there is no page to open.
    ///
    /// Lifted out of tvOS's free function `downloadDestination(for:library:)`, which already had
    /// this shape, so the Mac's downloads popover and library strip get the same answer without a
    /// second copy.
    @MainActor
    public func titleItem(in library: LibraryStore?) -> MediaItem? {
        guard tmdbID > 0 else { return nil }
        let isShow = status.contentKey.hasPrefix("show:")
        if isShow {
            if let owned = library?.shows.first(where: { $0.tmdbID == tmdbID }) { return owned }
        } else {
            if let owned = library?.movies.first(where: { $0.tmdbID == tmdbID }) { return owned }
        }
        return .placeholder(for: SearchHit(result: TMDBSearchResult(
            id: tmdbID, title: isShow ? nil : title, name: isShow ? title : nil,
            releaseDate: nil, firstAirDate: nil, posterPath: posterPath,
            overview: nil, voteAverage: nil), kind: isShow ? .show : .movie))
    }
}
