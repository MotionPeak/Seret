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
    private let cacheDirectory: URL
    private var token: String?

    /// Persistent on-disk cache for downloaded subtitle files, keyed by OpenSubtitles `file_id`.
    /// A re-download of the same file (re-watching a title) is served from here — no `POST /download`,
    /// so it doesn't spend the daily quota. Defaults to a Caches subfolder (survives app restarts).
    public static var defaultCacheDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appending(path: "SeretSubtitles")
    }

    public init(apiKey: String, credentials: Credentials,
                http: HTTPClient = HTTPClient(), userAgent: String = "Seret v1",
                cacheDirectory: URL = OpenSubtitlesProvider.defaultCacheDirectory) {
        self.apiKey = apiKey
        self.credentials = credentials
        self.http = http
        self.userAgent = userAgent
        self.cacheDirectory = cacheDirectory
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
        if let cached = cachedSubtitle(fileID: result.fileID) { return cached }   // reuse → no quota spend
        let dl = try await requestDownload(fileID: result.fileID)
        guard let link = URL(string: dl.link) else { throw SubtitleError.invalidResponse }
        let bytes = try await http.data(link)
        return try writeCacheFile(bytes, fileID: result.fileID, fileName: dl.fileName ?? result.fileName)
    }

    /// An already-cached subtitle file for this `file_id`, if one exists (prefix match — the
    /// extension was decided at download time). nil when the cache dir is missing or has no match.
    private func cachedSubtitle(fileID: Int) -> URL? {
        let prefix = "sub-\(fileID)."
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Writes subtitle bytes to the persistent cache, keyed by `file_id`. The name is `sub-<id>.<ext>`
    /// — `file_id` is our own numeric search result (not hostile server input), and only a safe
    /// extension is taken from the server `fileName` (default `srt`), so the path can't be influenced.
    private func writeCacheFile(_ data: Data, fileID: Int, fileName: String?) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let url = cacheDirectory.appending(path: "sub-\(fileID).\(Self.subtitleExtension(fileName))")
        try data.write(to: url, options: .atomic)
        return url
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

    private static let isoStyle = Date.ISO8601FormatStyle()

    static func parseResetTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return try? isoStyle.parse(value)
    }

    /// Returns the cached login token, logging in (once) if there isn't one.
    private func ensureToken() async throws -> String {
        if let token { return token }
        do {
            let response: OSLoginResponse = try await http.post(
                Self.base.appending(path: "login"),
                json: ["username": credentials.username, "password": credentials.password],
                headers: baseHeaders)
            token = response.token
            return response.token
        } catch let error as HTTPError {
            if case .status(let code, _) = error, code == 401 || code == 403 {
                throw SubtitleError.notAuthenticated
            }
            throw error
        }
    }

    private func authHeaders(_ token: String) -> [String: String] {
        var headers = baseHeaders
        headers["Authorization"] = "Bearer \(token)"
        return headers
    }

    /// A safe lowercased extension from `fileName` (letters only, ≤4 chars), else `srt`.
    static func subtitleExtension(_ fileName: String?) -> String {
        guard let fileName, let dot = fileName.lastIndex(of: "."),
              dot != fileName.index(before: fileName.endIndex) else { return "srt" }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return (ext.count <= 4 && ext.allSatisfy(\.isLetter)) ? ext : "srt"
    }
}
