import Vapor
import DebridCore

/// One playable version of a title. Deliberately carries only an `index` — the restricted RD
/// link never leaves the server.
struct VersionDTO: Content, Equatable {
    let index: Int
    let label: String
    let resolution: String?
}

/// A library entry as the browser sees it.
struct LibraryItemDTO: Content, Equatable {
    let id: String
    let kind: String
    let title: String
    let year: Int?
    let tmdbID: Int?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let versions: [VersionDTO]

    init(_ item: MediaItem) {
        self.id = item.id
        self.kind = item.kind.rawValue
        self.title = item.title
        self.year = item.year
        self.tmdbID = item.tmdbID
        self.posterPath = item.posterPath
        self.backdropPath = item.backdropPath
        self.overview = item.overview
        self.versions = item.sources.enumerated().map { index, media in
            let p = media.parsed
            let parts = [p.resolution, p.source, p.videoCodec].compactMap { $0 }
            return VersionDTO(index: index,
                              label: parts.isEmpty ? "Version \(index + 1)" : parts.joined(separator: " · "),
                              resolution: p.resolution)
        }
    }
}
