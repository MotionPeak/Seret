import Foundation

/// OpenSubtitles (api/v1) subtitle provider. An `actor` because it caches the login JWT.
/// `search` needs only the Api-Key; `download` (Task 4) needs a logged-in Bearer token.
public actor OpenSubtitlesProvider: SubtitleProvider {
    public struct Credentials: Sendable {
        public let username: String
        public let password: String
        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }

    public static let base = URL(string: "https://api.opensubtitles.com/api/v1")!

    private let apiKey: String
    private let credentials: Credentials
    private let http: HTTPClient
    private let userAgent: String
    private var token: String?

    public init(apiKey: String, credentials: Credentials,
                http: HTTPClient = HTTPClient(), userAgent: String = "Seret v1") {
        self.apiKey = apiKey
        self.credentials = credentials
        self.http = http
        self.userAgent = userAgent
    }

    private var baseHeaders: [String: String] { ["Api-Key": apiKey, "User-Agent": userAgent] }

    public func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        var items: [URLQueryItem] = []
        if let id = query.tmdbID {
            items.append(URLQueryItem(name: "tmdb_id", value: String(id)))
        } else {
            items.append(URLQueryItem(name: "query", value: query.title))
        }
        if !languages.isEmpty {
            items.append(URLQueryItem(name: "languages", value: languages.joined(separator: ",")))
        }
        if let s = query.season { items.append(URLQueryItem(name: "season_number", value: String(s))) }
        if let e = query.episode { items.append(URLQueryItem(name: "episode_number", value: String(e))) }

        var comps = URLComponents(url: Self.base.appending(path: "subtitles"), resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        let response: OSSearchResponse = try await http.get(comps.url!, headers: baseHeaders)
        return response.data.compactMap { sub in
            guard let file = sub.attributes.files.first else { return nil }
            return SubtitleResult(fileID: file.fileID,
                                  language: sub.attributes.language ?? "",
                                  release: sub.attributes.release,
                                  fileName: file.fileName,
                                  downloadCount: sub.attributes.downloadCount)
        }
    }

    public func download(_ result: SubtitleResult) async throws -> URL {
        let dl = try await requestDownload(fileID: result.fileID)
        guard let link = URL(string: dl.link) else { throw SubtitleError.invalidResponse }
        let bytes = try await http.data(link)
        return try Self.writeTempFile(bytes, fileName: dl.fileName ?? result.fileName)
    }

    private func requestDownload(fileID: Int) async throws -> OSDownloadResponse {
        do {
            return try await attemptDownload(fileID: fileID)
        } catch let error as HTTPError {
            guard case .status(let code, _) = error else { throw error }
            switch code {
            case 401:
                token = nil                                   // expired → re-login once and retry
                return try await attemptDownload(fileID: fileID)
            case 403, 406:
                throw SubtitleError.dailyCapReached(resetTime: nil)
            default:
                throw error
            }
        }
    }

    private func attemptDownload(fileID: Int) async throws -> OSDownloadResponse {
        let token = try await ensureToken()
        let response: OSDownloadResponse = try await http.post(
            Self.base.appending(path: "download"),
            json: ["file_id": fileID], headers: authHeaders(token))
        if let remaining = response.remaining, remaining <= 0 {
            throw SubtitleError.dailyCapReached(resetTime: Self.parseResetTime(response.resetTimeUTC))
        }
        return response
    }

    // ISO8601DateFormatter.date(from:) is documented thread-safe; nonisolated(unsafe) silences
    // the Swift 6 Sendable warning without wrapping in a lock or actor.
    private nonisolated(unsafe) static let resetTimeFormatter = ISO8601DateFormatter()

    static func parseResetTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return resetTimeFormatter.date(from: value)
    }

    /// Returns the cached login token, logging in (once) if there isn't one.
    private func ensureToken() async throws -> String {
        if let token { return token }
        let response: OSLoginResponse = try await http.post(
            Self.base.appending(path: "login"),
            json: ["username": credentials.username, "password": credentials.password],
            headers: baseHeaders)
        token = response.token
        return response.token
    }

    private func authHeaders(_ token: String) -> [String: String] {
        var headers = baseHeaders
        headers["Authorization"] = "Bearer \(token)"
        return headers
    }

    /// Writes subtitle bytes to a uniquely-named temp file, returning its URL. The name is a UUID
    /// (so a hostile server `file_name` cannot influence the path); only a safe extension is taken
    /// from the server name (default `srt`) to keep the format hint for the player.
    static func writeTempFile(_ data: Data, fileName: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).\(subtitleExtension(fileName))")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A safe lowercased extension from `fileName` (letters only, ≤4 chars), else `srt`.
    static func subtitleExtension(_ fileName: String?) -> String {
        guard let fileName, let dot = fileName.lastIndex(of: "."),
              dot != fileName.index(before: fileName.endIndex) else { return "srt" }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return (ext.count <= 4 && ext.allSatisfy(\.isLetter)) ? ext : "srt"
    }
}
