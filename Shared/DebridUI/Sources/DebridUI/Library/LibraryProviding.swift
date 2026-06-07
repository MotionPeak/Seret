import DebridCore

/// Thin seam over the brain's library API so `LibraryStore` is unit-testable without RD/TMDB.
/// Plain `Sendable` (NOT `@MainActor`): `LibraryService` is a Sendable struct with nonisolated
/// methods; the `@MainActor` store calls it across the boundary.
public protocol LibraryProviding: Sendable {
    func loadCached() -> [MediaItem]?
    func refresh() async throws -> [MediaItem]
    func remove(_ item: MediaItem) async throws
}

extension LibraryService: LibraryProviding {}
