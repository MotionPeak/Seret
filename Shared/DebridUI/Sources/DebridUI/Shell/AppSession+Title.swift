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
}
