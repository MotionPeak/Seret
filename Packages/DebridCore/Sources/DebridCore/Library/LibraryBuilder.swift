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
        // Shows are grouped by normalized title only (not year): episodes of one show can come
        // from torrents with inconsistent/absent years. Rare same-title-different-show collisions
        // are acceptable for v1; TMDB enrichment (Plan 5) refines identity.
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
                    id: "movie:\(Self.titleKey(parsed.title))\(parsed.year.map { ":\($0)" } ?? "")",
                    kind: .movie, title: parsed.title, year: parsed.year,
                    sources: [source], seasons: [], addedAt: Self.parseAdded(info.added)))
            }
        }

        let movieItems = movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let showItems = shows.values.map { $0.build() }
            .filter { !$0.seasons.isEmpty }   // drop shows that ended up with no episodes
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return movieItems + showItems
    }

    /// Adds a torrent's episode(s) to a show accumulator: a single-episode torrent
    /// contributes one episode; a season pack (season but no episode in the torrent name)
    /// is expanded by parsing each selected video file path for its episode number.
    private func ingestTV(_ info: TorrentInfo, _ parsed: ParsedRelease, into acc: ShowAccumulator) {
        acc.observe(added: Self.parseAdded(info.added))
        if let episode = parsed.episode, let primary = info.primaryVideoFile() {
            acc.add(season: parsed.season ?? 1, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: primary.file.id,
                                        restrictedLink: primary.link, parsed: parsed))
            return
        }
        // Season pack: expand selected video files.
        let packSeason = parsed.season ?? 1
        for (file, link) in info.selectedFilesWithLinks() where Self.isVideoPath(file.path) {
            let fileParsed = parser.parse(file.path)
            guard let episode = fileParsed.episode else { continue }
            acc.add(season: fileParsed.season ?? packSeason, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: file.id,
                                        restrictedLink: link, parsed: fileParsed))
        }
    }

    private static func isVideoPath(_ path: String) -> Bool {
        let video: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]
        return video.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    /// Normalized grouping key: lowercased letters+digits only, so "Dune.Part.Two"
    /// and "Dune Part Two" collapse together.
    static func titleKey(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Parses RD's ISO-8601 `added` timestamp (with or without fractional seconds).
    static func parseAdded(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// Mutable accumulator for a single show's episodes (deduped by season+episode).
private final class ShowAccumulator {
    let title: String
    let year: Int?
    private var episodes: [String: Episode] = [:]
    private(set) var newestAdded: Date?

    init(title: String, year: Int?) {
        self.title = title
        self.year = year
    }

    /// Tracks the most recent torrent `added` date across the show's torrents,
    /// so a freshly-added episode resurfaces the show in "Recently Added".
    func observe(added: Date?) {
        guard let added else { return }
        newestAdded = newestAdded.map { max($0, added) } ?? added
    }

    func add(season: Int, number: Int, source: MediaSource) {
        let episode = Episode(season: season, number: number, source: source)
        // Keep the first-seen source. RD returns newest torrents first, so this is usually the
        // preferred re-download. v2: prefer by resolution via source.parsed.resolution.
        if episodes[episode.id] == nil { episodes[episode.id] = episode }
    }

    func build() -> MediaItem {
        let bySeason = Dictionary(grouping: episodes.values, by: { $0.season })
        let seasons = bySeason.keys.sorted().map { number in
            Season(number: number, episodes: bySeason[number]!.sorted { $0.number < $1.number })
        }
        return MediaItem(id: "show:\(LibraryBuilder.titleKey(title))", kind: .show,
                         title: title, year: year, sources: [], seasons: seasons,
                         addedAt: newestAdded)
    }
}
