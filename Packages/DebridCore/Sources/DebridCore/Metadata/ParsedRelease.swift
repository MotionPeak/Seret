/// Structured fields extracted from a release name. All optional except `title`.
public struct ParsedRelease: Sendable, Equatable, Codable {
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
