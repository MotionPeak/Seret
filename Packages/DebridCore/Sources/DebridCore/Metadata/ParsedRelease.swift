/// Structured fields extracted from a release name. All optional except `title`.
public struct ParsedRelease: Sendable, Equatable, Hashable, Codable {
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var resolution: String?
    public var source: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var releaseGroup: String?

    public init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil,
                resolution: String? = nil, source: String? = nil, videoCodec: String? = nil,
                audioCodec: String? = nil, releaseGroup: String? = nil) {
        self.title = title; self.year = year; self.season = season; self.episode = episode
        self.resolution = resolution; self.source = source; self.videoCodec = videoCodec
        self.audioCodec = audioCodec; self.releaseGroup = releaseGroup
    }

    public var isTV: Bool { season != nil || episode != nil }
}

public extension ParsedRelease {
    /// This parse, with anything it does not state filled in from `fallback`.
    ///
    /// A file inside a season pack is often named far more sparsely than the pack itself — an
    /// episode may be plain `S01E03.mkv` while the resolution, source and codec are stated only on
    /// the torrent. Season, episode and title stay this parse's own: those are what make the file
    /// the episode it is.
    func completed(from fallback: ParsedRelease) -> ParsedRelease {
        ParsedRelease(title: title,
                      year: year ?? fallback.year,
                      season: season,
                      episode: episode,
                      resolution: resolution ?? fallback.resolution,
                      source: source ?? fallback.source,
                      videoCodec: videoCodec ?? fallback.videoCodec,
                      audioCodec: audioCodec ?? fallback.audioCodec,
                      releaseGroup: releaseGroup ?? fallback.releaseGroup)
    }
}
