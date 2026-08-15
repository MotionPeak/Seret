import DebridCore

extension SearchHit {
    /// The key this title's watch state hangs off — identical to the id its library `MediaItem`
    /// would carry, so a title watched from search and the same title in the library are one thing.
    public var contentKey: String { "\(kind.rawValue):tmdb:\(result.id)" }
}

extension MediaItem {
    /// A title you do not own yet, shaped so the Detail page can render it exactly like one you do.
    ///
    /// The id is the canonical `movie:tmdb:…` / `show:tmdb:…` form that `MetadataEnricher` gives a
    /// library item speaks. Getting this wrong is not cosmetic: the Add flow used to key playback as
    /// `tmdb:123`, so nothing — resume, Continue Watching, downloads — could find
    /// what you had watched.
    ///
    /// `sources` and `seasons` are empty by definition. `DetailStore.load()` fills in everything
    /// else from TMDB, the same call it makes for a library item.
    public static func placeholder(for hit: SearchHit) -> MediaItem {
        MediaItem(id: hit.contentKey,
                  kind: hit.kind,
                  title: hit.result.displayTitle,
                  year: hit.result.year,
                  sources: [],
                  seasons: [],
                  tmdbID: hit.result.id,
                  posterPath: hit.result.posterPath,
                  backdropPath: nil,
                  overview: hit.result.overview)
    }
}
