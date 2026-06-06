import Foundation

/// `StreamSource` backed by the Comet Stremio addon. Returns instantly-cached torrents
/// (config sets `cachedOnly:true`) for a title, with quality + languages parsed from each
/// stream's title text and the infohash/file-index parsed from its `/playback/` URL.
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
        let token = try await tokens.validAccessToken()
        let config = #"{"debridService":"realdebrid","debridApiKey":""# + token
            + #"","cachedOnly":true,"resultFormat":["all"]}"#
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
        return response.streams.compactMap { map($0) }
    }

    private func map(_ dto: CometStreamDTO) -> CachedStream? {
        guard let (hash, fileIdx) = Self.parsePlayback(dto.url) else { return nil }
        let text = dto.description ?? dto.name ?? ""
        let rawTitle = Self.torrentTitle(from: text) ?? dto.name ?? hash
        return CachedStream(
            infoHash: hash,
            fileIdx: fileIdx,
            rawTitle: rawTitle,
            parsed: parser.parse(rawTitle),
            languages: languages.detect(in: text),
            sizeBytes: dto.behaviorHints?.videoSize,
            sourceName: dto.name)
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
    }
}
