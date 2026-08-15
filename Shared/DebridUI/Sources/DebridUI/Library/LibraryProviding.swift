import DebridCore

/// Thin seam over the brain's library API so `LibraryStore` is unit-testable without RD/TMDB.
/// Plain `Sendable` (NOT `@MainActor`): `LibraryService` is a Sendable struct with nonisolated
/// methods; the `@MainActor` store calls it across the boundary.
public protocol LibraryProviding: Sendable {
    func loadCached() -> [MediaItem]?
    func refresh() async throws -> [MediaItem]
    func remove(_ item: MediaItem) async throws
    /// Remove ONE version (a `MediaSource`) of a movie. If it's the last source, removes the
    /// whole item. No-op on shows.
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws
}

public extension LibraryProviding {
    /// `loadCached()` off the main actor.
    ///
    /// It is a multi-megabyte JSON decode for a large Real-Debrid account, and its only production
    /// caller is a `@MainActor` store — so running it inline held the first frame of every launch
    /// and every retry. The default implementation is enough for every conformer; nothing about
    /// what is loaded changes, only which thread parses it.
    func loadCachedOffMain() async -> [MediaItem]? {
        await Task.detached(priority: .userInitiated) { self.loadCached() }.value
    }
}

extension LibraryService: LibraryProviding {}
