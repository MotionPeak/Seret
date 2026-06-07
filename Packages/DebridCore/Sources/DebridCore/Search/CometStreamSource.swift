import Foundation

/// `StreamSource` backed by the Comet Stremio addon. Returns cached (or optionally uncached)
/// torrents for a title, with quality + languages parsed from each stream's title text and
/// the infohash/file-index parsed from its `/playback/` URL.
public struct CometStreamSource: StreamSource {
    public static let defaultBaseURL = URL(string: "https://comet.elfhosted.com")!

    private let baseURL: URL
    private let http: HTTPClient
    private let tokens: any AccessTokenProviding
    private let parser: FilenameParser
    private let languages: LanguageDetector

    public init(baseURL: URL = CometStreamSource.defaultBaseURL,
                http: HTTPClient = HTTPClient(),
                tokens: any AccessTokenProviding,
                parser: FilenameParser = FilenameParser(),
                languages: LanguageDetector = LanguageDetector()) {
        self.baseURL = baseURL; self.http = http; self.tokens = tokens
        self.parser = parser; self.languages = languages
    }

    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        try await streams(for: query, includeUncached: false)
    }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        let token = try await tokens.validAccessToken()
        let cachedOnly = includeUncached ? "false" : "true"
        let config = #"{"debridService":"realdebrid","debridApiKey":""# + token
            + #"","cachedOnly":"# + cachedOnly + #","resultFormat":["all"]}"#
        let b64 = Data(config.utf8).base64EncodedString()

        let id: String
        let type: String
        switch query.kind {
        case .movie:
            type = "movie"; id = query.imdbID
        case let .series(season, episode):
            type = "series"; id = "\(query.imdbID):\(season):\(episode)"
        }

        let url = baseURL.appending(path: "\(b64)/stream/\(type)/\(id).json")
        let response: CometStreamResponse = try await http.get(url)
        let mapped = response.streams.compactMap { map($0) }
        return Self.validate(mapped, against: query)
    }

    /// Drops releases that don't correspond to the requested title — the indexer keys on IMDB id
    /// and its scrapers mis-attribute same-named junk (old films, porn) to a new/generic title.
    /// A query with no title (back-compat) is left unfiltered.
    static func validate(_ streams: [CachedStream], against query: StreamQuery) -> [CachedStream] {
        guard let title = query.title, !title.isEmpty else { return streams }
        let matcher = ReleaseMatcher()
        switch query.kind {
        case .movie:
            return streams.filter { matcher.matchesMovie($0.parsed, title: title, year: query.year) }
        case .series:
            return streams.filter { matcher.matchesSeries($0.parsed, title: title) }
        }
    }

    private func map(_ dto: CometStreamDTO) -> CachedStream? {
        // The public elfhosted instance ENCRYPTS the `/playback/` path, so the infohash is no
        // longer plaintext in the URL. It's still exposed in `behaviorHints.bingeGroup`
        // ("comet|<service>|<40-hex>"). Prefer that; fall back to a plaintext
        // `/playback/{40-hex}/…/{fileIdx}/` path (vanilla Comet / MediaFusion drop-in).
        let fromURL = Self.parsePlayback(dto.url)
        guard let hash = Self.infoHash(fromBingeGroup: dto.behaviorHints?.bingeGroup) ?? fromURL?.hash else {
            return nil
        }
        let text = dto.description ?? dto.name ?? ""
        // The real release name is the richest signal for quality parsing; prefer the
        // filename, then the description's first line.
        let rawTitle = dto.behaviorHints?.filename ?? Self.torrentTitle(from: text) ?? dto.name ?? hash
        return CachedStream(
            infoHash: hash,
            fileIdx: fromURL?.fileIdx,   // only recoverable from an unencrypted URL
            rawTitle: rawTitle,
            parsed: parser.parse(rawTitle),
            languages: languages.detect(in: text),
            sizeBytes: dto.behaviorHints?.videoSize,
            sourceName: dto.name,
            isCached: Self.isCachedName(dto.name))
    }

    /// Comet flags cache state in the stream `name`: "⚡" = cached/instant, "⬇" = will-download.
    /// No marker (or nil) → treat as not cached.
    static func isCachedName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.contains("⚡")
    }

    /// Pulls the 40-hex infohash out of a Comet `behaviorHints.bingeGroup`
    /// ("comet|realdebrid|<40-hex>"). Returns nil when absent or malformed.
    static func infoHash(fromBingeGroup group: String?) -> String? {
        guard let last = group?.split(separator: "|").last else { return nil }
        let hash = last.lowercased()
        guard hash.count == 40, hash.allSatisfy(\.isHexDigit) else { return nil }
        return hash
    }

    /// Extracts (infohash, fileIdx?) from `…/playback/{hash}/{entry}/{fileIdx}/{s}/{e}`.
    /// Returns nil when the url has no `/playback/<40-hex>/` segment.
    static func parsePlayback(_ urlString: String?) -> (hash: String, fileIdx: Int?)? {
        guard let urlString, let range = urlString.range(of: "/playback/") else { return nil }
        let tail = urlString[range.upperBound...]
        let segments = tail.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = segments.first else { return nil }
        let hash = String(first)
        guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        // segments: [hash, entry, fileIdx, season, episode...] — fileIdx is index 2.
        var fileIdx: Int? = nil
        if segments.count > 2 {
            let raw = segments[2].split(separator: "?").first.map(String.init) ?? String(segments[2])
            fileIdx = Int(raw)  // "n" → nil
        }
        return (hash, fileIdx)
    }

    /// First description line, stripped of the leading "📄 " marker.
    static func torrentTitle(from description: String) -> String? {
        guard let firstLine = description.split(separator: "\n").first else { return nil }
        let trimmed = firstLine.drop(while: { $0 == "📄" || $0 == " " })
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}

// MARK: - Wire DTOs (Comet/Stremio stream response)

struct CometStreamResponse: Decodable { let streams: [CometStreamDTO] }

struct CometStreamDTO: Decodable {
    let name: String?
    let description: String?
    let url: String?
    let behaviorHints: BehaviorHints?

    struct BehaviorHints: Decodable {
        let videoSize: Int?
        let filename: String?
        let bingeGroup: String?
    }
}
