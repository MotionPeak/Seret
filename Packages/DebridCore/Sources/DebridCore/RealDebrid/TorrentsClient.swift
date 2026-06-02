import Foundation

/// Reads the user's Real-Debrid library and resolves playable URLs.
public struct TorrentsClient: Sendable {
    /// Real-Debrid REST resource base — distinct from the OAuth base in `RealDebridAuthClient`.
    public static let base = URL(string: "https://api.real-debrid.com/rest/1.0")!

    private let http: HTTPClient
    private let tokens: any AccessTokenProviding

    public init(http: HTTPClient = HTTPClient(), tokens: any AccessTokenProviding) {
        self.http = http
        self.tokens = tokens
    }

    private func authHeaders() async throws -> [String: String] {
        ["Authorization": "Bearer \(try await tokens.validAccessToken())"]
    }

    /// One page of the user's torrents (RD paginates; default page size 100).
    public func torrents(page: Int = 1, limit: Int = 100) async throws -> [Torrent] {
        var comps = URLComponents(url: Self.base.appending(path: "torrents"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
        ]
        return try await http.get(comps.url!, headers: try await authHeaders())
    }

    /// Files + restricted links for a single torrent.
    public func info(id: String) async throws -> TorrentInfo {
        try await http.get(Self.base.appending(path: "torrents/info/\(id)"),
                           headers: try await authHeaders())
    }
}
