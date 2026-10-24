import Foundation

/// What `createtorrent` answers. Decoded with `.convertFromSnakeCase` like every TorBox payload;
/// some responses name the id `torrent_id`, others `id`, and a batch answers an array.
private struct CreatedTorrent: Decodable {
    let torrentId: Int?
    let id: Int?
    let hash: String?

    var resolvedID: Int? { torrentId ?? id }
}

private struct CheckCachedBody: Encodable {
    let hashes: [String]
}

extension TorBoxClient {
    /// `checkcached` accepts a bounded list per call.
    static let checkCachedChunk = 100

    // MARK: - DebridClient

    public func add(magnetHash: String) async throws -> TorrentInfo {
        try await add(magnetHash: magnetHash, maxPollAttempts: 10)
    }

    public func addForDownload(magnetHash: String) async throws -> TorrentInfo {
        let hash = magnetHash.lowercased()
        if let existing = try await existingTorrent(hash: hash) {
            return try await info(id: existing.id)
        }
        let id = try await create(hash: hash, onlyIfCached: false)
        return try await info(id: TorBoxMapping.torrentID(id))
    }

    // MARK: - Instant add

    /// Adds an instantly-cached torrent and waits until it is playable. An already-ready torrent
    /// with that hash is returned as it is. `sleep` is injected so tests pass a no-op.
    ///
    /// `add_only_if_cached` makes TorBox refuse an uncached torrent up front
    /// (`DOWNLOAD_NOT_CACHED` -> `RDAddError.notInstant`) rather than start downloading it.
    public func add(magnetHash: String,
                    maxPollAttempts: Int = 10,
                    pollInterval: Duration = .seconds(1),
                    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TorrentInfo {
        let hash = magnetHash.lowercased()
        if let existing = try await existingTorrent(hash: hash), existing.status == "downloaded" {
            return try await info(id: existing.id)
        }

        let numeric = try await create(hash: hash, onlyIfCached: true)
        let id = TorBoxMapping.torrentID(numeric)
        do {
            var current = try await info(id: id)
            var attempts = 0
            while current.status != "downloaded" && attempts < maxPollAttempts {
                if current.status == "error" { throw RDAddError.failed(status: current.status, torrentID: id) }
                try await sleep(pollInterval)
                current = try await info(id: id)
                attempts += 1
            }
            if current.status == "error" { throw RDAddError.failed(status: current.status, torrentID: id) }
            guard current.status == "downloaded" else { throw RDAddError.notInstant(torrentID: id) }
            return current
        } catch {
            // A torrent that never became playable would sit in the account (and in every later
            // refresh). Remove it so the caller can fall back to the next version.
            try? await deleteTorrent(id: id)
            throw error
        }
    }

    // MARK: - Cached check

    /// The subset of `hashes` TorBox already has cached, lowercased. TorBox answers `data: null`
    /// when none are.
    public func checkCached(hashes: [String]) async throws -> Set<String> {
        var cached = Set<String>()
        var start = 0
        while start < hashes.count {
            let chunk = Array(hashes[start..<min(start + Self.checkCachedChunk, hashes.count)])
            start += Self.checkCachedChunk
            let found: [String: Ignored]? = try await post(
                "torrents/checkcached",
                query: [.init(name: "format", value: "object"), .init(name: "list_files", value: "false")],
                body: CheckCachedBody(hashes: chunk))
            cached.formUnion((found ?? [:]).keys.map { $0.lowercased() })
        }
        return cached
    }

    // MARK: - Helpers

    private func existingTorrent(hash: String) async throws -> Torrent? {
        try await allTorrents().first { $0.hash.lowercased() == hash }
    }

    /// `POST createtorrent`; returns TorBox's numeric torrent id.
    private func create(hash: String, onlyIfCached: Bool) async throws -> Int {
        var form = [
            "magnet": "magnet:?xt=urn:btih:\(hash)",
            "seed": "3",
            "allow_zip": "false",
        ]
        if onlyIfCached { form["add_only_if_cached"] = "true" }

        let created: OneOrMany<CreatedTorrent>?
        do {
            created = try await postForm("torrents/createtorrent", form: form)
        } catch let TorBoxError.api(code, _, _) where code == "DOWNLOAD_NOT_CACHED" {
            throw RDAddError.notInstant(torrentID: "")
        } catch let TorBoxError.api(code, _, _) where code == "BOZO_TORRENT" || code == "DOWNLOAD_TOO_LARGE" {
            throw RDAddError.failed(status: code, torrentID: "")
        }
        // A batch answer can list several torrents; take the one for this hash.
        let items = created?.items ?? []
        let match = items.count == 1 ? items.first : items.first { $0.hash?.lowercased() == hash }
        guard let id = match?.resolvedID else {
            throw TorBoxError.api(code: "NO_TORRENT_ID", detail: "TorBox did not return a torrent id.", status: 502)
        }
        return id
    }
}
