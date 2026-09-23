import DebridCore

// `AppSession.swift` itself belongs to `feat/mobile-parity` — this extension keeps M3's addition
// out of that file entirely, in a new file of its own.
extension AppSession {
    /// The acquire/download engine for one title page. Wired from the page's own `DetailStore` so
    /// the imdbID / originalLanguage — which land only once `load()` completes — are read lazily
    /// rather than captured at construction, when they are still nil.
    public func makeTitleAcquirer(for store: DetailStore,
                                  onAdded: (@MainActor () -> Void)? = nil) -> TitleAcquirer {
        TitleAcquirer(
            item: store.item,
            makeAcquisition: { [weak self] in
                guard let self else { return nil }
                return self.makeAcquisition(for: store.item, imdbID: store.imdbID,
                                            originalLanguage: store.originalLanguage)
            },
            makeSeasonPack: { [weak self] season in
                guard let self, let imdbID = store.imdbID else { return nil }
                return self.makeSeasonDownload(imdbID: imdbID, season: season,
                                               originalLanguage: store.originalLanguage)
            },
            downloads: downloadStore,
            onAdded: onAdded ?? { [weak self] in self?.libraryStore?.reload() })
    }

    /// The Versions sheet's engine for one movie/episode target, built from a `MediaItem` the way
    /// tvOS's `VersionsScreen` built its `SearchHit` — by hand from the item, since a title page
    /// already has one and gains nothing from a fresh search. nil when the item has no TMDB id.
    public func makeVersionsModel(for item: MediaItem, target: AcquisitionStore.Target) -> VersionsModel? {
        guard let tmdbID = item.tmdbID else { return nil }
        let hit = SearchHit(result: TMDBSearchResult(
            id: tmdbID, title: item.kind == .movie ? item.title : nil,
            name: item.kind == .show ? item.title : nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: item.kind)
        return VersionsModel(hit: hit, target: target, flow: makeAddFlow(for: hit),
                             downloads: downloadStore,
                             onAdded: { [weak self] in self?.libraryStore?.reload() })
    }
}
