import Foundation

/// What the library, player and download flows need from a debrid service. Real-Debrid's
/// `TorrentsClient` is the reference implementation; the models it returns are provider-neutral.
public protocol DebridClient: Sendable {
    var provider: DebridProvider { get }

    func torrents(page: Int, limit: Int) async throws -> [Torrent]
    func allTorrents() async throws -> [Torrent]
    /// The account's torrents plus any providers that could not answer. A single-provider client
    /// either answers or throws, so the default reports nothing unavailable.
    func listTorrents() async throws -> TorrentListing
    func info(id: String) async throws -> TorrentInfo
    func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo]
    func unrestrict(link: String) async throws -> UnrestrictedLink
    func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink?
    func deleteTorrent(id: String) async throws
    /// Adds an instantly-cached torrent and waits until it is playable.
    func add(magnetHash: String) async throws -> TorrentInfo
    /// Adds a torrent and returns immediately so the provider downloads it in the background.
    func addForDownload(magnetHash: String) async throws -> TorrentInfo
}

extension DebridClient {
    public func listTorrents() async throws -> TorrentListing {
        TorrentListing(torrents: try await allTorrents())
    }
}

extension TorrentsClient: DebridClient {
    public var provider: DebridProvider { .realDebrid }

    // `TorrentsClient`'s own methods carry defaulted parameters (page size, poll budget,
    // concurrency). Swift does not let a defaulted method witness a requirement with fewer
    // parameters, so these exact-signature overloads forward with RD's defaults — behaviour is
    // unchanged.

    public func allTorrents() async throws -> [Torrent] {
        try await allTorrents(pageSize: 100)
    }

    public func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo] {
        try await allTorrentInfos(from: list, maxConcurrent: 5)
    }

    public func add(magnetHash: String) async throws -> TorrentInfo {
        try await add(magnetHash: magnetHash, maxPollAttempts: 10)
    }

    public func addForDownload(magnetHash: String) async throws -> TorrentInfo {
        try await addForDownload(magnetHash: magnetHash, maxListAttempts: 10)
    }
}
