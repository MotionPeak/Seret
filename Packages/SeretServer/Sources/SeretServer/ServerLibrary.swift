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

    /// Built serially on purpose, and deliberately NOT via `MetadataEnricher.enrich(_:maxConcurrent:)`.
    ///
    /// That batch helper declares a local `func add(_:)` which captures the `TaskGroup`. `TaskGroup`
    /// is non-escapable, so capturing it in a nested function and calling it later from the
    /// `for await` loop is unsafe: it happens to work on Darwin, but on Linux/Swift 6.3 it corrupts
    /// the group's bookkeeping and traps inside `out[index] = enriched`
    /// (`Array.subscript.modify`, MetadataEnricher.swift:71) — confirmed from a container backtrace.
    /// The single-item `enrich(_:)` has no task group and is safe. The library is cached, so paying
    /// for a serial pass once is irrelevant.
    @discardableResult
    func refresh() async throws -> [MediaItem] {
        let infos = try await torrents.allTorrentInfos(maxConcurrent: 1)
        let grouped = builder.group(infos)

        var enriched: [MediaItem] = []
        enriched.reserveCapacity(grouped.count)
        for item in grouped {
            // A per-item lookup failure must never fail the whole library.
            enriched.append((try? await enricher.enrich(item)) ?? item)
        }

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
