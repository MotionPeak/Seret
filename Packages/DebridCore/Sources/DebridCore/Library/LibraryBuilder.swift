import Foundation

/// Turns Real-Debrid torrents into an organized library. Pure and synchronous —
/// parses each torrent name, classifies it, and groups episodes per show.
/// TMDB enrichment and RD fetching live elsewhere (Plan 5 / app layer).
public struct LibraryBuilder: Sendable {
    private let parser: FilenameParser

    public init(parser: FilenameParser = FilenameParser()) {
        self.parser = parser
    }

    public func group(_ infos: [TorrentInfo]) -> [MediaItem] {
        var movies: [MediaItem] = []
        var shows: [String: ShowAccumulator] = [:]

        for info in infos {
            let parsed = parser.parse(info.filename)
            if parsed.isTV {
                let key = Self.titleKey(parsed.title)
                let acc = shows[key] ?? ShowAccumulator(title: parsed.title, year: parsed.year)
                ingestTV(info, parsed, into: acc)
                shows[key] = acc
            } else if let primary = info.primaryVideoFile() {
                let source = MediaSource(torrentID: info.id, fileID: primary.file.id,
                                         restrictedLink: primary.link, parsed: parsed)
                movies.append(MediaItem(
                    id: "movie:\(Self.titleKey(parsed.title)):\(parsed.year.map(String.init) ?? "")",
                    kind: .movie, title: parsed.title, year: parsed.year,
                    sources: [source], seasons: []))
            }
        }

        let movieItems = movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let showItems = shows.values.map { $0.build() }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return movieItems + showItems
    }

    /// Adds a torrent's episode(s) to a show accumulator. Task 2 handles single episodes;
    /// the next task adds season-pack expansion.
    private func ingestTV(_ info: TorrentInfo, _ parsed: ParsedRelease, into acc: ShowAccumulator) {
        if let episode = parsed.episode, let primary = info.primaryVideoFile() {
            acc.add(season: parsed.season ?? 1, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: primary.file.id,
                                        restrictedLink: primary.link, parsed: parsed))
        }
    }

    /// Normalized grouping key: lowercased letters+digits only, so "Dune.Part.Two"
    /// and "Dune Part Two" collapse together.
    static func titleKey(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Mutable accumulator for a single show's episodes (deduped by season+episode).
final class ShowAccumulator {
    let title: String
    let year: Int?
    private var episodes: [String: Episode] = [:]

    init(title: String, year: Int?) {
        self.title = title
        self.year = year
    }

    func add(season: Int, number: Int, source: MediaSource) {
        let episode = Episode(season: season, number: number, source: source)
        if episodes[episode.id] == nil { episodes[episode.id] = episode }   // keep first
    }

    func build() -> MediaItem {
        let bySeason = Dictionary(grouping: episodes.values, by: { $0.season })
        let seasons = bySeason.keys.sorted().map { number in
            Season(number: number, episodes: bySeason[number]!.sorted { $0.number < $1.number })
        }
        return MediaItem(id: "show:\(LibraryBuilder.titleKey(title))", kind: .show,
                         title: title, year: year, sources: [], seasons: seasons)
    }
}
