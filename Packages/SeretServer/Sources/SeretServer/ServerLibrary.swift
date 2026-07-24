import Foundation
import DebridCore

/// Builds and caches the TMDB-organized library for the web face.
///
/// Named `ServerLibrary` rather than `LibraryService` because DebridCore already owns a
/// `LibraryService` (the apps' cache-first, SwiftData-backed one). The server keeps its
/// library purely in memory — no snapshot store on Linux.
actor ServerLibrary {
    private let torrents: TorrentsClient
    private let enricher: MetadataEnricher
    private let builder = LibraryBuilder()
    private var cache: [MediaItem] = []

    init(torrents: TorrentsClient, enricher: MetadataEnricher) {
        self.torrents = torrents
        self.enricher = enricher
    }

    var items: [MediaItem] { cache }
    var isEmpty: Bool { cache.isEmpty }
    func item(id: String) -> MediaItem? { cache.first { $0.id == id } }

    @discardableResult
    func refresh() async throws -> [MediaItem] {
        let infos = try await torrents.allTorrentInfos()
        let grouped = builder.group(infos)
        let enriched = await enricher.enrich(grouped)
        cache = Self.mergeDuplicates(enriched)
        return cache
    }

    /// Enrichment rekeys each movie to its TMDB id, but one torrent produces one item — so the
    /// same film added several times yields several items sharing a tmdbID. Collapse those into
    /// a single entry carrying every version, preserving first-seen order.
    static func mergeDuplicates(_ items: [MediaItem]) -> [MediaItem] {
        var order: [String] = []
        var byKey: [String: MediaItem] = [:]
        for (i, item) in items.enumerated() {
            let key: String
            if item.kind == .movie, let tmdb = item.tmdbID { key = "movie:\(tmdb)" } else { key = "unique:\(i)" }
            if let existing = byKey[key] {
                byKey[key] = MediaItem(
                    id: existing.id, kind: existing.kind, title: existing.title,
                    year: existing.year ?? item.year,
                    sources: existing.sources + item.sources,
                    seasons: existing.seasons, tmdbID: existing.tmdbID,
                    posterPath: existing.posterPath ?? item.posterPath,
                    backdropPath: existing.backdropPath ?? item.backdropPath,
                    overview: existing.overview ?? item.overview)
            } else {
                order.append(key)
                byKey[key] = item
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
