import Foundation
import DebridCore

/// Builds the one merged debrid account the server runs on: Real-Debrid and/or TorBox, whichever
/// the config carries. Both use a static key held in memory — no Keychain, no refresh — the same
/// static-Bearer path the apps use for paste-token sign-in. Real-Debrid comes first (display and
/// add-fallback order).
func makeDebridClient(_ config: ServerConfig) async throws -> CompositeDebridClient {
    var clients: [any DebridClient] = []
    if let rdToken = config.rdToken {
        let session = RealDebridSession(store: InMemoryTokenStore())
        try await session.establishStaticToken(rdToken)
        clients.append(SerialInfoDebridClient(TorrentsClient(tokens: session)))
    }
    if let torBoxKey = config.torBoxAPIKey {
        let session = TorBoxSession(store: InMemorySecretStore())
        try await session.establish(key: torBoxKey)
        clients.append(TorBoxClient(tokens: session))
    }
    guard !clients.isEmpty else { throw ServerConfig.ConfigError.missing("RD_TOKEN or TORBOX_API_KEY") }
    return CompositeDebridClient(clients: clients, addTarget: config.addTarget ?? clients[0].provider)
}

/// Real-Debrid with its per-torrent `info` fan-out kept SERIAL, exactly as the server ran before
/// the provider seam existed (`allTorrentInfos(maxConcurrent: 1)`): the protocol's
/// `allTorrentInfos(from:)` forwards to RD's default of 5 in flight, and this server is the one
/// that was pinned to 1 to stay clear of RD's rate limit (and the Linux TaskGroup trap noted in
/// `ServerLibrary`). Everything else forwards untouched.
struct SerialInfoDebridClient: DebridClient {
    private let base: TorrentsClient
    init(_ base: TorrentsClient) { self.base = base }

    var provider: DebridProvider { base.provider }
    func torrents(page: Int, limit: Int) async throws -> [Torrent] { try await base.torrents(page: page, limit: limit) }
    func allTorrents() async throws -> [Torrent] { try await base.allTorrents() }
    func info(id: String) async throws -> TorrentInfo { try await base.info(id: id) }
    func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo] {
        try await base.allTorrentInfos(from: list, maxConcurrent: 1)
    }
    func unrestrict(link: String) async throws -> UnrestrictedLink { try await base.unrestrict(link: link) }
    func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? { try await base.playableURL(for: info) }
    func deleteTorrent(id: String) async throws { try await base.deleteTorrent(id: id) }
    func add(magnetHash: String) async throws -> TorrentInfo { try await base.add(magnetHash: magnetHash) }
    func addForDownload(magnetHash: String) async throws -> TorrentInfo { try await base.addForDownload(magnetHash: magnetHash) }
}
