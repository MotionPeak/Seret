import Foundation

/// `StreamSource` backed by the public Torrentio addon — a broad, tokenless torrent index that
/// (unlike elfhosted's Comet) carries brand-new releases (CAM/TELESYNC). It returns raw torrents
/// with no debrid cache info, so every result is `isCached:false` (⬇️ Download): it contributes
/// only to the uncached "Show all versions / Request Download" path, never the instant Play path.
public struct TorrentioStreamSource: StreamSource {
    public static let defaultBaseURL = URL(string: "https://torrentio.strem.fun")!

    private let baseURL: URL
    private let http: HTTPClient
    private let parser: FilenameParser
    private let languages: LanguageDetector
    private let matcher = ReleaseMatcher()

    public init(baseURL: URL = TorrentioStreamSource.defaultBaseURL,
                http: HTTPClient = HTTPClient(),
                parser: FilenameParser = FilenameParser(),
                languages: LanguageDetector = LanguageDetector()) {
        self.baseURL = baseURL; self.http = http; self.parser = parser; self.languages = languages
    }

    /// Cached-only: Torrentio can't confirm RD-instant availability, so it stays out of the Play path.
    public func streams(for query: StreamQuery) async throws -> [CachedStream] { [] }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        guard includeUncached else { return [] }
        let id: String
        let type: String
        switch query.kind {
        case .movie:
            type = "movie"; id = query.imdbID
        case let .series(season, episode):
            type = "series"; id = "\(query.imdbID):\(season):\(episode)"
        }
        let url = baseURL.appending(path: "stream/\(type)/\(id).json")
        let response: TorrentioResponse = try await http.get(url)
        let mapped = response.streams.compactMap { map($0) }
        return validate(mapped, against: query)
    }

    private func map(_ dto: TorrentioStreamDTO) -> CachedStream? {
        guard let raw = dto.infoHash?.lowercased(), raw.count == 40, raw.allSatisfy(\.isHexDigit) else {
            return nil
        }
        let text = dto.title ?? dto.name ?? ""
        // First line of `title` is the release name; `behaviorHints.filename` is cleaner when present.
        let rawTitle = dto.behaviorHints?.filename
            ?? text.split(separator: "\n").first.map(String.init)
            ?? dto.name ?? raw
        return CachedStream(
            infoHash: raw,
            fileIdx: dto.fileIdx,
            rawTitle: rawTitle,
            parsed: parser.parse(rawTitle),
            languages: languages.detect(in: text),
            sizeBytes: Self.parseSize(text),
            sourceName: "Torrentio",
            isCached: false)
    }

    /// Same gate as Comet: keep only releases that match the requested title (year for movies,
    /// title-only for series), excluding mis-attributed series / wrong-year / wrong-film junk.
    private func validate(_ streams: [CachedStream], against query: StreamQuery) -> [CachedStream] {
        guard let title = query.title, !title.isEmpty else { return streams }
        switch query.kind {
        case .movie:
            return streams.filter { matcher.matchesMovie($0.parsed, title: title, year: query.year) }
        case .series:
            return streams.filter { matcher.matchesSeries($0.parsed, title: title) }
        }
    }

    private static let reSize = try! NSRegularExpression(pattern: #"([\d.]+)\s*(GB|MB)"#, options: [.caseInsensitive])

    /// Pulls a byte count out of Torrentio's title text (e.g. "💾 5.34 GB" → 5_340_000_000).
    static func parseSize(_ text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = Self.reSize.firstMatch(in: text, range: range),
              let numR = Range(m.range(at: 1), in: text), let unitR = Range(m.range(at: 2), in: text),
              let value = Double(text[numR]) else { return nil }
        let unit = text[unitR].uppercased()
        // `value` comes from an untrusted third-party title; a huge/garbage digit run can make the
        // product exceed Int.max, and `Int(Double)` TRAPS (crashes) out of range — guard before converting.
        let product = value * (unit == "GB" ? 1_000_000_000.0 : 1_000_000.0)
        guard product.isFinite, product >= 0, product < Double(Int.max) else { return nil }
        return Int(product)
    }
}

// MARK: - Wire DTOs (Torrentio stream response)

struct TorrentioResponse: Decodable { let streams: [TorrentioStreamDTO] }

struct TorrentioStreamDTO: Decodable {
    let name: String?
    let title: String?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: BehaviorHints?

    struct BehaviorHints: Decodable { let filename: String? }
}
