import Vapor
import DebridCore

/// One playable version of a title. Deliberately carries only an `index` — the restricted RD
/// link never leaves the server. `index` is the position in `item.sources` (what `/watch?version=`
/// expects); the list itself is ordered best-first, mirroring the app's Versions list.
struct VersionDTO: Content, Equatable {
    let index: Int
    let label: String
    let resolution: String?
    /// "Hebrew · Built in" / "Hebrew · Matched", nil when there is nothing to say.
    let hebrew: String?

    /// Versions best-first — Hebrew first when the evidence says so — each carrying its original
    /// `item.sources` index for playback.
    static func list(for item: MediaItem, subtitles: SubtitleEvidenceSet = .empty) -> [VersionDTO] {
        item.sources.bestFirst(subtitles: subtitles).map { source in
            let index = item.sources.firstIndex(of: source) ?? 0
            let p = source.parsed
            let parts = [p.resolution, p.source, p.videoCodec, p.audioCodec].compactMap { $0 }
            return VersionDTO(index: index,
                              label: parts.isEmpty ? "Version \(index + 1)" : parts.joined(separator: " · "),
                              resolution: p.resolution,
                              hebrew: subtitles.hebrew(forVersion: WatchKey.source(source)).badgeText)
        }
    }
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
    let addedAt: Double?   // epoch seconds; drives the "Recently Added" rail
    let versions: [VersionDTO]

    init(_ item: MediaItem, subtitles: SubtitleEvidenceSet) {
        self.id = item.id
        self.kind = item.kind.rawValue
        self.title = item.title
        self.year = item.year
        self.tmdbID = item.tmdbID
        self.posterPath = item.posterPath
        self.backdropPath = item.backdropPath
        self.overview = item.overview
        self.addedAt = item.addedAt.map { $0.timeIntervalSince1970 }
        self.versions = VersionDTO.list(for: item, subtitles: subtitles)
    }

    init(_ item: MediaItem) { self.init(item, subtitles: .empty) }
}

/// DTOs with each multi-version movie's copies in the order its title page plays them. Stored
/// evidence only: a library page must not wait on probes.
func libraryDTOs(_ items: [MediaItem], evidence: SubtitleEvidenceService?) async -> [LibraryItemDTO] {
    var dtos: [LibraryItemDTO] = []
    for item in items {
        if let evidence, item.sources.count > 1 {
            dtos.append(LibraryItemDTO(item, subtitles: await evidence.storedEvidence(for: item.sources,
                                                                                      contentKey: item.id)))
        } else {
            dtos.append(LibraryItemDTO(item))
        }
    }
    return dtos
}
