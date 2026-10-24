import Foundation

/// Reads the user's TorBox library and resolves playable URLs. TorBox's counterpart to
/// `TorrentsClient`; everything it returns is the shared `Torrent` / `TorrentInfo` currency.
///
/// Every call goes through one of the two private helpers, which own the `{success, error, detail,
/// data}` envelope and the error mapping, so no call site can forget either.
///
/// Never log a request URL from here: `requestdl` carries the account key in its query string
/// (TorBox requires that), and its response is a time-limited stream URL.
public struct TorBoxClient: DebridClient {
    public static let base = URL(string: "https://api.torbox.app/v1")!

    /// `mylist` page size for the whole-library fetch.
    static let defaultPageSize = 1000

    private let http: HTTPClient
    private let tokens: any AccessTokenProviding

    public init(http: HTTPClient = HTTPClient(), tokens: any AccessTokenProviding) {
        self.http = http
        self.tokens = tokens
    }

    public var provider: DebridProvider { .torBox }

    // MARK: - Library

    public func torrents(page: Int, limit: Int) async throws -> [Torrent] {
        try await myList(page: page, limit: limit).map(TorBoxMapping.torrent)
    }

    public func allTorrents() async throws -> [Torrent] {
        try await allTorrents(pageSize: Self.defaultPageSize)
    }

    /// Follows `mylist` pagination until a page comes back short.
    func allTorrents(pageSize: Int) async throws -> [Torrent] {
        try await allMyList(pageSize: pageSize).map(TorBoxMapping.torrent)
    }

    public func info(id: String) async throws -> TorrentInfo {
        guard let numeric = TorBoxMapping.numericID(id) else {
            throw TorBoxError.api(code: "BAD_ID", detail: "Not a TorBox torrent id.", status: 400)
        }
        let one: OneOrMany<TorBoxTorrent>? = try await get(
            "torrents/mylist",
            query: [.init(name: "bypass_cache", value: "true"), .init(name: "id", value: String(numeric))])
        guard let torrent = one?.items.first else {
            throw TorBoxError.api(code: "NOT_FOUND", detail: "TorBox has no such torrent.", status: 404)
        }
        return TorBoxMapping.info(torrent)
    }

    /// TorBox's `mylist` already carries each torrent's files, so there is no per-torrent fan-out:
    /// ONE paged list call, filtered to the requested ids. A torrent that is no longer on the
    /// account is skipped, matching the Real-Debrid client's "a failed fetch is dropped".
    public func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo] {
        let all = try await allMyList(pageSize: Self.defaultPageSize)
        let byID = Dictionary(all.map { (TorBoxMapping.torrentID($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        // List order, like the RD client's callers expect; `added` rides on `createdAt` in the mapping.
        return list.compactMap { byID[$0.id].map(TorBoxMapping.info) }
    }

    // MARK: - Playback

    /// Mints a time-limited stream URL for one file of a torrent. Resolve this right before playback.
    public func unrestrict(link: String) async throws -> UnrestrictedLink {
        guard let handle = TorBoxMapping.parseLink(link) else {
            throw TorBoxError.api(code: "BAD_LINK", detail: "Not a TorBox link.", status: 400)
        }
        // TorBox requires the key as a query parameter on this one endpoint.
        let key = try await tokens.validAccessToken()
        let url: String? = try await get(
            "torrents/requestdl",
            query: [.init(name: "token", value: key),
                    .init(name: "torrent_id", value: String(handle.torrentID)),
                    .init(name: "file_id", value: String(handle.fileID))])
        guard let url, !url.isEmpty else {
            throw TorBoxError.api(code: "NO_LINK", detail: "TorBox returned no stream URL.", status: 502)
        }
        return UnrestrictedLink(download: url, filename: "", filesize: 0, mimeType: nil)
    }

    public func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? {
        guard let primary = info.primaryVideoFile() else { return nil }
        return try await unrestrict(link: primary.link)
    }

    // MARK: - Account

    public func deleteTorrent(id: String) async throws {
        guard let numeric = TorBoxMapping.numericID(id) else {
            throw TorBoxError.api(code: "BAD_ID", detail: "Not a TorBox torrent id.", status: 400)
        }
        let _: Ignored? = try await post(
            "torrents/controltorrent", body: ControlTorrent(torrentID: numeric, operation: "delete"))
    }

    public func user() async throws -> TorBoxUser {
        let user: TorBoxUser? = try await get("user/me", query: [.init(name: "settings", value: "false")])
        guard let user else {
            throw TorBoxError.api(code: "NO_DATA", detail: "TorBox returned no account.", status: 502)
        }
        return user
    }

    // MARK: - Adding (Task 4)

    public func add(magnetHash: String) async throws -> TorrentInfo {
        throw TorBoxError.api(code: "NOT_IMPLEMENTED", detail: "", status: 0)
    }

    public func addForDownload(magnetHash: String) async throws -> TorrentInfo {
        throw TorBoxError.api(code: "NOT_IMPLEMENTED", detail: "", status: 0)
    }

    // MARK: - Listing helpers

    private func myList(page: Int, limit: Int) async throws -> [TorBoxTorrent] {
        let list: OneOrMany<TorBoxTorrent>? = try await get(
            "torrents/mylist",
            query: [.init(name: "bypass_cache", value: "true"),
                    .init(name: "offset", value: String((max(page, 1) - 1) * limit)),
                    .init(name: "limit", value: String(limit))])
        return list?.items ?? []
    }

    private func allMyList(pageSize: Int) async throws -> [TorBoxTorrent] {
        precondition(pageSize > 0, "pageSize must be positive")
        var all: [TorBoxTorrent] = []
        var page = 1
        while true {
            let batch = try await myList(page: page, limit: pageSize)
            all.append(contentsOf: batch)
            if batch.count < pageSize { break }
            page += 1
        }
        return all
    }

    // MARK: - Transport + envelope (the only place either lives)

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T? {
        var comps = URLComponents(url: Self.base.appending(path: "api/\(path)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        let headers = try await authHeaders()
        let data: Data
        do {
            data = try await http.data(comps.url!, headers: headers)
        } catch let HTTPError.status(code, body) {
            throw Self.error(status: code, body: body)
        }
        return try Self.unwrap(data)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T? {
        let url = Self.base.appending(path: "api/\(path)")
        let headers = try await authHeaders()
        let envelope: TorBoxEnvelope<T>
        do {
            // The envelope's own keys are single words, so the client's default decoder reads
            // them; the payloads this is used for are `Ignored`.
            envelope = try await http.post(url, json: body, headers: headers)
        } catch let HTTPError.status(code, bodyText) {
            throw Self.error(status: code, body: bodyText)
        }
        return try Self.unwrap(envelope)
    }

    private func authHeaders() async throws -> [String: String] {
        ["Authorization": "Bearer \(try await tokens.validAccessToken())"]
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static func unwrap<T: Decodable>(_ data: Data) throws -> T? {
        let envelope: TorBoxEnvelope<T>
        do {
            envelope = try decoder().decode(TorBoxEnvelope<T>.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
        return try unwrap(envelope)
    }

    /// A 200 with `success == false` is still a failure.
    private static func unwrap<T>(_ envelope: TorBoxEnvelope<T>) throws -> T? {
        guard envelope.success else {
            throw TorBoxError.api(code: envelope.error ?? "UNKNOWN", detail: envelope.detail ?? "", status: 200)
        }
        return envelope.data
    }

    /// Maps a non-2xx answer. A 429 means the key is locked out for about five minutes: report it
    /// and let the caller back off — never retry. `HTTPError.status` carries no headers, so the
    /// `Retry-After` value is not available here.
    private static func error(status: Int, body: String) -> TorBoxError {
        if status == 429 { return .rateLimited(retryAfter: nil) }
        let envelope = try? decoder().decode(TorBoxEnvelope<Ignored>.self, from: Data(body.utf8))
        return .api(code: envelope?.error ?? "HTTP_\(status)", detail: envelope?.detail ?? "", status: status)
    }
}

// MARK: - Wire helpers

/// `mylist?id=` answers a single object; the unfiltered list answers an array.
private struct OneOrMany<T: Decodable>: Decodable {
    let items: [T]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([T].self) {
            items = many
        } else {
            items = [try container.decode(T.self)]
        }
    }
}

/// A payload nobody reads (`controltorrent` answers `data: null`).
private struct Ignored: Decodable {}

private struct ControlTorrent: Encodable {
    let torrentID: Int
    let operation: String

    enum CodingKeys: String, CodingKey {
        case torrentID = "torrent_id"
        case operation
    }
}
