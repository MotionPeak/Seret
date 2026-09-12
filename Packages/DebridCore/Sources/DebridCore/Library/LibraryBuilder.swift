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

        // Sorted, because `allTorrentInfos` fans out concurrently and hands them back in
        // completion order. A show's displayed title and year come from whichever of its torrents
        // is seen FIRST, so an unsorted input meant two torrents whose names normalise to the same
        // show ("It's Always Sunny" and "Its.Always.Sunny") could show a different title on every
        // refresh. Same torrents in, same library out.
        for info in infos.sorted(by: { $0.id < $1.id }) {
            let parsed = parser.parse(info.filename)
            if parsed.isTV {
                let key = Self.titleKey(parsed.title)
                let acc = shows[key] ?? ShowAccumulator(title: parsed.title, year: parsed.year)
                ingestTV(info, parsed, into: acc)
                shows[key] = acc
            } else if let primary = info.primaryVideoFile() {
                let source = MediaSource(torrentID: info.id, fileID: primary.file.id,
                                         restrictedLink: primary.link, parsed: parsed,
                                         sizeBytes: primary.file.bytes)
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
        let packSeason = parsed.season ?? 1
        if let episode = parsed.episode {
            // The torrent NAME states one episode — but a pack added through RD is routinely named
            // after the first episode it contains, because that is what the indexer titled it. So
            // the name is only a hint; the FILES are the truth.
            //
            // When the files name more than one distinct episode, this is a pack and expanding it
            // is the only way the rest of them reach the library. Branching on the name alone added
            // the named episode and returned, so a season the viewer added showed exactly one
            // episode and the other nine were never looked at.
            if Self.distinctEpisodes(of: info, season: packSeason, parser: parser).count > 1 {
                expand(info, packSeason: packSeason, into: acc)
                return
            }
            // A single episode after all. Prefer the file that actually NAMES it — `primaryVideoFile()`
            // (the largest) would return the wrong one in a mis-named torrent while the row still
            // records progress under the clicked episode. Fall back to the largest video when no
            // file names it, so an oddly-named single-episode torrent is not dropped.
            guard let primary = info.videoFile(forSeason: parsed.season, episode: episode)
                ?? info.primaryVideoFile() else { return }
            acc.add(season: packSeason, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: primary.file.id,
                                        restrictedLink: primary.link, parsed: parsed,
                                        sizeBytes: primary.file.bytes))
            return
        }
        expand(info, packSeason: packSeason, into: acc)
    }

    /// Every (season, episode) the torrent's own selected video files name. The season falls back
    /// to the pack's, so files that name only an episode still group together rather than looking
    /// like distinct entries.
    private static func distinctEpisodes(of info: TorrentInfo, season packSeason: Int,
                                         parser: FilenameParser) -> Set<SeasonEpisode> {
        var keys: Set<SeasonEpisode> = []
        for (file, _) in info.selectedFilesWithLinks() where isVideoPath(file.path) {
            let parsed = parser.parse(file.path)
            guard let episode = parsed.episode else { continue }
            keys.insert(SeasonEpisode(season: parsed.season ?? packSeason, number: episode))
        }
        return keys
    }

    /// Add one episode per selected video file that names one — the season-pack expansion.
    private func expand(_ info: TorrentInfo, packSeason: Int, into acc: ShowAccumulator) {
        // Files inside a pack are often named far more sparsely than the pack itself — an episode
        // may be plain `S01E03.mkv` while the resolution, source and codec are stated only on the
        // torrent. Take the file's own parse and fall back to the torrent's for whatever it omits,
        // or expanding a pack would strip the quality the ranker and the Versions list depend on.
        let packParsed = parser.parse(info.filename)
        for (file, link) in info.selectedFilesWithLinks() where Self.isVideoPath(file.path) {
            let fileParsed = parser.parse(file.path)
            guard let episode = fileParsed.episode else { continue }
            acc.add(season: fileParsed.season ?? packSeason, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: file.id,
                                        restrictedLink: link,
                                        parsed: fileParsed.completed(from: packParsed),
                                        sizeBytes: file.bytes))
        }
    }

    private static func isVideoPath(_ path: String) -> Bool {
        let video: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]
        return video.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    /// One episode's place in a show — just enough to count how many DISTINCT episodes a torrent's
    /// files name.
    struct SeasonEpisode: Hashable {
        let season: Int
        let number: Int
    }

    /// Normalized grouping key: lowercased letters+digits only, so "Dune.Part.Two"
    /// and "Dune Part Two" collapse together.
    static func titleKey(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Parses RD's ISO-8601 `added` timestamp (with or without fractional seconds).
    static func parseAdded(_ string: String?) -> Date? { ISO8601Timestamp.date(from: string) }
}

/// Mutable accumulator for a single show's episodes (deduped by season+episode).
private final class ShowAccumulator {
    let title: String
    let year: Int?
    /// Every owned copy per `season+episode`, in arrival order. Ranked into primary + alternates
    /// at `build()` time, so ordering depends on quality rather than on which torrent RD listed
    /// first.
    private var episodeSources: [String: (season: Int, number: Int, sources: [MediaSource])] = [:]
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
        let key = "s\(season)e\(number)"
        // Keep EVERY copy. This used to be first-writer-wins, which discarded the other copies of
        // an episode you own — so the survivor was whichever torrent RD happened to list first,
        // not the best one, and there was no way to reach the rest. It also left the player with a
        // single source, making "Try another version" permanently unavailable for episodes.
        var entry = episodeSources[key] ?? (season: season, number: number, sources: [])
        // The identical file arriving twice (the same torrent re-ingested) is one copy.
        guard !entry.sources.contains(where: {
            $0.torrentID == source.torrentID && $0.fileID == source.fileID
        }) else { return }
        entry.sources.append(source)
        episodeSources[key] = entry
    }

    func build() -> MediaItem {
        // Rank at build time, not on arrival: ordering must depend on quality, not on the order RD
        // returned torrents, or the same library would order differently between refreshes.
        let episodes = episodeSources.values.map { entry -> Episode in
            let ranked = entry.sources.bestFirst()
            return Episode(season: entry.season, number: entry.number,
                           source: ranked[0], alternates: Array(ranked.dropFirst()))
        }
        let bySeason = Dictionary(grouping: episodes, by: { $0.season })
        let seasons = bySeason.keys.sortedBySeason().map { number in
            Season(number: number, episodes: bySeason[number]!.sorted { $0.number < $1.number })
        }
        return MediaItem(id: "show:\(LibraryBuilder.titleKey(title))", kind: .show,
                         title: title, year: year, sources: [], seasons: seasons,
                         addedAt: newestAdded)
    }
}
