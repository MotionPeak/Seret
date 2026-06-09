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

    /// Adds a magnet to the user's RD account. Returns the new torrent's id.
    /// `POST /torrents/addMagnet` (form `magnet`). RD returns 201. A copyright-flagged torrent is
    /// refused with HTTP 451 `infringing_file` — mapped to `RDAddError.blocked` so the UI can say
    /// so (retrying or trying another version of a blocked torrent never helps).
    public func addMagnet(magnet: String) async throws -> AddMagnetResponse {
        do {
            return try await http.post(Self.base.appending(path: "torrents/addMagnet"),
                                       form: ["magnet": magnet],
                                       headers: try await authHeaders())
        } catch let HTTPError.status(_, body) where body.contains("infringing_file") {
            throw RDAddError.blocked
        }
    }

    /// Selects which files of a torrent to download. `files` is RD's raw param:
    /// the literal `"all"` or a comma-separated list of file ids ("1,2,3").
    /// `POST /torrents/selectFiles/{id}` returns 204.
    public func selectFiles(torrentID: String, files: String) async throws {
        try await http.postForm(Self.base.appending(path: "torrents/selectFiles/\(torrentID)"),
                                form: ["files": files],
                                headers: try await authHeaders())
    }

    /// Removes a torrent from the user's RD account. `DELETE /torrents/delete/{id}` (204).
    /// Used to clean up a torrent that failed to instant-add so it doesn't pollute the library.
    public func deleteTorrent(id: String) async throws {
        try await http.delete(Self.base.appending(path: "torrents/delete/\(id)"),
                              headers: try await authHeaders())
    }

    /// Terminal RD failure statuses for the add flow.
    private static let errorStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]

    /// High-level add for an instantly-cached torrent: addMagnet → wait for file listing →
    /// selectFiles(all) → wait for `downloaded` → return its `TorrentInfo`. Because the torrent
    /// is already cached, RD resolves it in seconds. Throws `RDAddError.notInstant` if it does
    /// not reach `downloaded` within `maxPollAttempts`, or `.failed` on a terminal status.
    /// `sleep` is injected for testability (pass a no-op in tests).
    public func add(magnetHash: String,
                    maxPollAttempts: Int = 10,
                    pollInterval: Duration = .seconds(1),
                    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TorrentInfo {
        let added = try await addMagnet(magnet: "magnet:?xt=urn:btih:\(magnetHash)")
        let id = added.id
        do {
            return try await selectAndAwaitDownloaded(id: id, maxPollAttempts: maxPollAttempts,
                                                      pollInterval: pollInterval, sleep: sleep)
        } catch {
            // ElfCache "cached" ≠ guaranteed instant for THIS account: a non-instant add leaves
            // a stuck/`magnet_error` torrent. Remove it so it doesn't pollute the library, then
            // rethrow so the caller (Get best) can fall back to the next version.
            try? await deleteTorrent(id: id)
            throw error
        }
    }

    /// Add a magnet and select its video files for download, then return immediately — does NOT
    /// wait for `downloaded` and does NOT delete on non-instant (that's the whole point: we want
    /// RD to download an uncached torrent in the background). Throws `RDAddError.failed` on a
    /// terminal status seen while waiting for the file listing. The caller monitors progress.
    public func addForDownload(magnetHash: String,
                               maxListAttempts: Int = 10,
                               pollInterval: Duration = .seconds(1),
                               sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TorrentInfo {
        let added = try await addMagnet(magnet: "magnet:?xt=urn:btih:\(magnetHash)")
        let id = added.id
        var info = try await self.info(id: id)
        var attempts = 0
        while info.files.isEmpty && info.status != "waiting_files_selection" && attempts < maxListAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }
        if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
        let videoIDs = info.videoFileIDs()
        let filesParam = videoIDs.isEmpty ? "all" : videoIDs.map(String.init).joined(separator: ",")
        try await selectFiles(torrentID: id, files: filesParam)
        return try await self.info(id: id)
    }

    private func selectAndAwaitDownloaded(id: String, maxPollAttempts: Int, pollInterval: Duration,
                                          sleep: @Sendable (Duration) async throws -> Void) async throws -> TorrentInfo {
        // 1) Wait until RD has listed files / is ready for selection.
        var info = try await self.info(id: id)
        var attempts = 0
        while info.files.isEmpty && info.status != "waiting_files_selection" && attempts < maxPollAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }

        // 2) Select ONLY the video files — selecting "all" pulls in thumbnails/.nfo/.sqlite
        //    junk, and RD then returns links only for the real media, breaking the file↔link
        //    pairing so the player can't find a playable file. Fall back to "all" if none parse.
        let videoIDs = info.videoFileIDs()
        let filesParam = videoIDs.isEmpty ? "all" : videoIDs.map(String.init).joined(separator: ",")
        try await selectFiles(torrentID: id, files: filesParam)

        // 3) Wait for the cached torrent to flip to `downloaded`.
        info = try await self.info(id: id)
        attempts = 0
        while info.status != "downloaded" && attempts < maxPollAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }
        guard info.status == "downloaded" else { throw RDAddError.notInstant(torrentID: id) }
        return info
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
    public func allTorrentInfos(maxConcurrent: Int = 5) async throws -> [TorrentInfo] {
        let list = try await allTorrents()
        // Bounded fan-out: at most `maxConcurrent` `/torrents/info` calls in flight. An unbounded
        // burst (one per torrent) tripped RD's rate limit on larger libraries → 429 thrash + stalls.
        let infos = await withTaskGroup(of: TorrentInfo?.self) { group in
            var next = 0, running = 0
            func add(_ i: Int) { let id = list[i].id; group.addTask { try? await self.info(id: id) } }
            while next < list.count && running < maxConcurrent { add(next); next += 1; running += 1 }
            var infos: [TorrentInfo] = []
            for await result in group {
                if let result { infos.append(result) }
                if next < list.count { add(next); next += 1 } else { running -= 1 }
            }
            return infos
        }
        // `/torrents/info/{id}` omits `added`; carry it from the `/torrents` list (by id) so
        // the library can surface a "Recently Added" rail.
        return Self.attachAddedDates(infos: infos, torrents: list)
    }

    /// Attaches each torrent's `added` timestamp (from the `/torrents` list) onto its
    /// `TorrentInfo` (whose own `added` is nil from `/torrents/info/{id}`), matched by id.
    static func attachAddedDates(infos: [TorrentInfo], torrents: [Torrent]) -> [TorrentInfo] {
        let addedByID = Dictionary(torrents.map { ($0.id, $0.added) }, uniquingKeysWith: { first, _ in first })
        return infos.map { info in
            guard let added = addedByID[info.id] else { return info }
            return TorrentInfo(id: info.id, filename: info.filename, hash: info.hash, bytes: info.bytes,
                               progress: info.progress, status: info.status, files: info.files,
                               links: info.links, added: added)
        }
    }
}
