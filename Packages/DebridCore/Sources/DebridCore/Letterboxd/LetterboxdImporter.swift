import Foundation

/// Fills local ratings in from the owner's public Letterboxd profile.
///
/// Resolution is the expensive step, so only films that could actually benefit are resolved: a
/// title Seret has already rated is skipped before any network call, because local wins and the
/// answer could not change the outcome.
public actor LetterboxdImporter {
    public struct Summary: Sendable, Equatable {
        public let scanned: Int
        public let needingWork: Int
        public let written: Int
        public let conflicts: Int
        public let unresolved: Int

        public init(scanned: Int, needingWork: Int, written: Int, conflicts: Int, unresolved: Int) {
            self.scanned = scanned
            self.needingWork = needingWork
            self.written = written
            self.conflicts = conflicts
            self.unresolved = unresolved
        }
    }

    public struct Progress: Sendable, Equatable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    private let reader: any LetterboxdProfileReading
    private let resolver: any LetterboxdFilmResolving
    private let map: LetterboxdFilmMap
    private let mapStore: LetterboxdFilmMapStore
    private let store: LocalWatchStore
    private let resolveDelay: Duration

    public init(reader: any LetterboxdProfileReading,
                resolver: any LetterboxdFilmResolving,
                map: LetterboxdFilmMap,
                mapStore: LetterboxdFilmMapStore,
                store: LocalWatchStore,
                resolveDelay: Duration = .milliseconds(400)) {
        self.reader = reader
        self.resolver = resolver
        self.map = map
        self.mapStore = mapStore
        self.store = store
        self.resolveDelay = resolveDelay
    }

    public func run(movies: [MediaItem],
                    profileID: String,
                    onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> Summary {
        // Films only: Letterboxd has no television, and a show key is not a film key.
        let films = movies.filter { LetterboxdContentKey.tmdbID(fromMovieKey: $0.id) != nil }

        let ratings = try await reader.films()
            .reduce(into: [String: Int]()) { out, entry in
                if let rating = entry.rating { out[entry.slug] = rating }
            }

        // Every film is resolved, not just the unrated ones. Skipping the rated ones would be
        // cheaper, but a disagreement can only be seen by resolving the film — so `conflicts` would
        // be structurally always zero and "you rated this differently here" could never be said.
        // Resolution is cached permanently, so this is a one-time cost per film either way.
        //
        // `WatchState` carries playback position, not the rating, so ratings are read directly.
        var candidates: [LetterboxdImportPlanner.Candidate] = []
        var unresolved = 0
        var needingWork = 0
        var done = 0

        for film in films {
            guard let tmdbID = LetterboxdContentKey.tmdbID(fromMovieKey: film.id) else { continue }

            let existingRating = try await store.rating(forContentKey: film.id, profileID: profileID)
            if existingRating == nil { needingWork += 1 }

            let alreadyKnown = await map.slug(forTMDB: tmdbID) != nil
            var slug: String?
            do {
                let resolved = try await resolver.slug(forTMDB: tmdbID)
                // The importer records what it learned rather than trusting the resolver to do it.
                // The map is what makes resolution a one-time cost, so owning that here keeps the
                // seam honest: a resolver only has to answer the question.
                await map.store(resolved, forTMDB: tmdbID)
                slug = resolved
            } catch {
                slug = nil
                unresolved += 1
            }
            candidates.append(LetterboxdImportPlanner.Candidate(
                contentKey: film.id, slug: slug, existingRating: existingRating))

            done += 1
            onProgress?(Progress(done: done, total: films.count))

            // Only pace actual network calls; a cached slug costs nothing and waits for nothing.
            if !alreadyKnown, resolveDelay > .zero, done < films.count {
                try await Task.sleep(for: resolveDelay)
            }
        }

        let plan = LetterboxdImportPlanner.plan(candidates: candidates, letterboxdRatings: ratings)
        for write in plan.writes {
            try await store.setRating(write.rating, contentKey: write.contentKey, profileID: profileID)
        }

        mapStore.save(await map.snapshot())

        return Summary(scanned: films.count,
                       needingWork: needingWork,
                       written: plan.writes.count,
                       conflicts: plan.conflicts.count,
                       unresolved: unresolved)
    }
}
