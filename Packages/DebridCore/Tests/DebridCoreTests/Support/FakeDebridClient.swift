import Foundation
@testable import DebridCore

/// Why a `FakeDebridClient` refused a call. Names the provider so a test can tell which account
/// a routed call actually reached.
enum FakeDebridError: Error, Equatable {
    case down(DebridProvider)
}

/// Records every routed call a `FakeDebridClient` receives, so routing tests can assert where a
/// call landed and that a call did NOT land somewhere.
final class FakeDebridCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// An in-memory debrid account. Every answer is derived from `listed`, and every call either
/// succeeds or — when `failing` — throws `FakeDebridError.down(provider)`, the way an API blip would.
struct FakeDebridClient: DebridClient {
    let provider: DebridProvider
    var listed: [Torrent] = []
    var failing = false
    var log = FakeDebridCallLog()

    private func check(_ call: String) throws {
        log.record("\(provider.rawValue).\(call)")
        if failing { throw FakeDebridError.down(provider) }
    }

    func torrents(page: Int, limit: Int) async throws -> [Torrent] {
        try check("torrents")
        return Array(listed.dropFirst((page - 1) * limit).prefix(limit))
    }

    func allTorrents() async throws -> [Torrent] {
        try check("allTorrents")
        return listed
    }

    func info(id: String) async throws -> TorrentInfo {
        try check("info(\(id))")
        let torrent = listed.first { $0.id == id }
            ?? Self.torrent(id, provider: provider, filename: "\(id).mkv")
        return Self.info(of: torrent, provider: provider)
    }

    func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo] {
        try check("allTorrentInfos(\(list.map(\.id).joined(separator: ",")))")
        return list.map { Self.info(of: $0, provider: provider) }
    }

    func unrestrict(link: String) async throws -> UnrestrictedLink {
        try check("unrestrict(\(link))")
        return UnrestrictedLink(download: "https://\(provider.rawValue).example/\(link)",
                                filename: provider.rawValue, filesize: 0, mimeType: nil)
    }

    func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? {
        try check("playableURL(\(info.id))")
        return UnrestrictedLink(download: "https://\(provider.rawValue).example/\(info.id)",
                                filename: provider.rawValue, filesize: 0, mimeType: nil)
    }

    func deleteTorrent(id: String) async throws {
        try check("deleteTorrent(\(id))")
    }

    func add(magnetHash: String) async throws -> TorrentInfo {
        try check("add(\(magnetHash))")
        return Self.info(of: Self.torrent(newID, provider: provider, filename: magnetHash), provider: provider)
    }

    func addForDownload(magnetHash: String) async throws -> TorrentInfo {
        try check("addForDownload(\(magnetHash))")
        return Self.info(of: Self.torrent(newID, provider: provider, filename: magnetHash,
                                          status: "downloading"), provider: provider)
    }

    private var newID: String { provider == .torBox ? "tb:new" : "NEW" }

    // MARK: - Builders

    /// A torrent as the provider lists it. TorBox ids carry their `tb:` prefix already.
    static func torrent(_ id: String, provider: DebridProvider = .realDebrid, filename: String,
                        status: String = "downloaded", progress: Double? = nil) -> Torrent {
        Torrent(id: id, filename: filename, hash: "h-\(id)", bytes: 1,
                host: provider == .torBox ? "torbox" : "real-debrid.com",
                progress: progress ?? (status == "downloaded" ? 100 : 40), status: status,
                added: "2024-01-01T00:00:00Z",
                links: status == "downloaded" ? [link(id, provider: provider)] : [])
    }

    /// One selected video file named after the torrent, with the provider's link shape.
    static func info(of torrent: Torrent, provider: DebridProvider) -> TorrentInfo {
        let ready = torrent.status == "downloaded"
        return TorrentInfo(id: torrent.id, filename: torrent.filename, hash: torrent.hash,
                           bytes: torrent.bytes, progress: torrent.progress, status: torrent.status,
                           files: ready ? [TorrentFile(id: 1, path: "/\(torrent.filename)", bytes: 1, selected: 1)] : [],
                           links: ready ? [link(torrent.id, provider: provider)] : [],
                           added: torrent.added)
    }

    static func link(_ id: String, provider: DebridProvider) -> String {
        provider == .torBox ? "torbox://\(id)/1" : "https://real-debrid.com/d/\(id)"
    }
}
