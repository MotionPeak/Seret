import Foundation

/// A film resolver that writes its slug map back to disk as it learns.
///
/// Without it a slug is re-resolved once per launch per film, which is the single most expensive
/// part of reading Letterboxd. Slugs never change, so the write is worth making the moment one is
/// learned — and only then: a map that already knows the answer must not cost a disk write on
/// every title page.
public struct PersistingFilmResolver: LetterboxdFilmResolving {
    private let resolver: any LetterboxdFilmResolving
    private let map: LetterboxdFilmMap
    private let store: LetterboxdFilmMapStore

    public init(resolver: any LetterboxdFilmResolving,
                map: LetterboxdFilmMap,
                store: LetterboxdFilmMapStore) {
        self.resolver = resolver
        self.map = map
        self.store = store
    }

    public func slug(forTMDB id: Int) async throws -> String {
        let alreadyKnown = await map.slug(forTMDB: id) != nil
        let slug = try await resolver.slug(forTMDB: id)
        if !alreadyKnown { store.save(await map.snapshot()) }
        return slug
    }
}
