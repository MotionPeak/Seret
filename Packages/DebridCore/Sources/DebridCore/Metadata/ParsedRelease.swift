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
    /// The name says the picture is not what its resolution claims: an AI upscale, a
    /// frame-interpolated film, a faked HDR grade. Such a version is never Play's pick.
    public var isUpscaled: Bool = false

    public init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil,
                resolution: String? = nil, source: String? = nil, videoCodec: String? = nil,
                audioCodec: String? = nil, releaseGroup: String? = nil) {
        self.title = title; self.year = year; self.season = season; self.episode = episode
        self.resolution = resolution; self.source = source; self.videoCodec = videoCodec
        self.audioCodec = audioCodec; self.releaseGroup = releaseGroup
    }

    public var isTV: Bool { season != nil || episode != nil }

    private enum CodingKeys: String, CodingKey {
        case title, year, season, episode, resolution, source, videoCodec, audioCodec, releaseGroup, isUpscaled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        videoCodec = try c.decodeIfPresent(String.self, forKey: .videoCodec)
        audioCodec = try c.decodeIfPresent(String.self, forKey: .audioCodec)
        releaseGroup = try c.decodeIfPresent(String.self, forKey: .releaseGroup)
        // Absent from every parse stored before the flag existed.
        isUpscaled = try c.decodeIfPresent(Bool.self, forKey: .isUpscaled) ?? false
    }
}

public extension ParsedRelease {
    /// This parse, with anything it does not state filled in from `fallback`.
    ///
    /// A file inside a season pack is often named far more sparsely than the pack itself — an
    /// episode may be plain `S01E03.mkv` while the resolution, source and codec are stated only on
    /// the torrent. Season, episode and title stay this parse's own: those are what make the file
    /// the episode it is.
    func completed(from fallback: ParsedRelease) -> ParsedRelease {
        var completed = ParsedRelease(title: title,
                      year: year ?? fallback.year,
                      season: season,
                      episode: episode,
                      resolution: resolution ?? fallback.resolution,
                      source: source ?? fallback.source,
                      videoCodec: videoCodec ?? fallback.videoCodec,
                      audioCodec: audioCodec ?? fallback.audioCodec,
                      releaseGroup: releaseGroup ?? fallback.releaseGroup)
        // A pack named as an upscale holds upscaled episodes, however plainly each file is named.
        completed.isUpscaled = isUpscaled || fallback.isUpscaled
        return completed
    }
}
