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

    /// Turns an RD restricted link into a directly-streamable URL. Resolve this lazily,
    /// right before playback — unrestricted URLs expire.
    public func unrestrict(link: String) async throws -> UnrestrictedLink {
        try await http.post(Self.base.appending(path: "unrestrict/link"),
                            form: ["link": link],
                            headers: try await authHeaders())
    }

    /// Convenience: pick the torrent's primary video file and unrestrict its link.
    /// Returns nil if the torrent has no selected video file.
    public func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? {
        guard let primary = info.primaryVideoFile() else { return nil }
        return try await unrestrict(link: primary.link)
    }

    /// Every torrent in the library, following RD's pagination (100 per page).
    ///
    /// Stops when a page returns fewer than `pageSize` items, so a library whose size is an
    /// exact multiple of `pageSize` incurs one extra (empty) page request before terminating.
    public func allTorrents(pageSize: Int = 100) async throws -> [Torrent] {
        precondition(pageSize > 0, "pageSize must be positive")
        var all: [Torrent] = []
        var page = 1
        while true {
            let batch = try await torrents(page: page, limit: pageSize)
            all.append(contentsOf: batch)
            if batch.count < pageSize { break }
            page += 1
        }
        return all
    }

    /// Every torrent's detailed info (files + links), fetched concurrently. A torrent whose
    /// info fetch fails is skipped rather than failing the whole load.
    public func allTorrentInfos() async throws -> [TorrentInfo] {
        let list = try await allTorrents()
        return await withTaskGroup(of: TorrentInfo?.self) { group in
            for torrent in list {
                // TODO: fan-out is currently unbounded; add a concurrency cap once RD
                // rate-limit behavior is characterised (v1-descoped).
                group.addTask { try? await self.info(id: torrent.id) }
            }
            var infos: [TorrentInfo] = []
            for await result in group {
                if let result { infos.append(result) }
            }
            return infos
        }
    }
}
