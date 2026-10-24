import Foundation

/// A call named a provider the viewer is not signed in to — a TorBox torrent id after signing out
/// of TorBox, say. Thrown instead of handing the id to the other account, which would only answer
/// with a confusing 404.
public enum DebridRoutingError: Error, Equatable, Sendable, LocalizedError {
    case notSignedIn(DebridProvider)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn(let provider): return "You're not signed in to \(provider.displayName)."
        }
    }
}

/// Every signed-in debrid account behind one `DebridClient`, so the library, player and download
/// flows see one merged account.
///
/// - Reads of one torrent or link go to the account that issued it (`DebridProvider.of`).
/// - Adds go to the add target.
/// - Listing asks every account at once and keeps whatever answered: one account's API blip must
///   not look like that account's torrents were deleted. `listTorrents()` names the accounts that
///   failed in `unavailable`, and throws only when every account failed.
public struct CompositeDebridClient: DebridClient {
    private let clients: [any DebridClient]
    private let addTarget: DebridProvider

    /// - Parameters:
    ///   - clients: the signed-in accounts, in display order. Must not be empty.
    ///   - addTarget: where adds go. Falls back to the first client when that account is not here.
    public init(clients: [any DebridClient], addTarget: DebridProvider) {
        precondition(!clients.isEmpty, "CompositeDebridClient needs at least one signed-in account")
        self.clients = clients
        self.addTarget = clients.contains { $0.provider == addTarget } ? addTarget : clients[0].provider
    }

    /// The effective add target.
    public var provider: DebridProvider { addTarget }

    /// Every signed-in provider, in client order.
    public var providers: [DebridProvider] { clients.map(\.provider) }

    public func client(for provider: DebridProvider) -> (any DebridClient)? {
        clients.first { $0.provider == provider }
    }

    private func routed(_ provider: DebridProvider) throws -> any DebridClient {
        guard let client = client(for: provider) else { throw DebridRoutingError.notSignedIn(provider) }
        return client
    }

    // MARK: - Listing

    /// Each account's same page, concatenated. Strict: a plain `[Torrent]` page has no way to say
    /// an account was missing, and a caller would read that account's torrents as deleted — so any
    /// failure throws. `listing(page:limit:)` is the partial-failure variant.
    public func torrents(page: Int, limit: Int) async throws -> [Torrent] {
        try await eachClient { try await $0.torrents(page: page, limit: limit) }
            .flatMap { try $0.result.get() }
    }

    /// The torrents of every account that answered. A caller that must tell "deleted" from "could
    /// not ask" uses `listTorrents()` instead.
    public func allTorrents() async throws -> [Torrent] {
        try await listTorrents().torrents
    }

    public func listTorrents() async throws -> TorrentListing {
        try Self.partial(await eachClient { try await $0.listTorrents() }) { $0 }
    }

    /// One page of every account, naming the accounts that failed — what the download monitor polls.
    /// Throws only when every account failed.
    ///
    /// The monitor reads a recorded download missing from page 1 as removed, which is sound for
    /// Real-Debrid (newest first) but not for TorBox, whose `mylist` order is undocumented. So
    /// TorBox answers its WHOLE list on page 1 — one call, since `mylist` carries everything and
    /// costs nothing per torrent — and nothing on later pages.
    public func listing(page: Int, limit: Int) async throws -> TorrentListing {
        try Self.partial(await eachClient { client in
            guard client.provider == .torBox else { return try await client.torrents(page: page, limit: limit) }
            return page <= 1 ? try await client.allTorrents() : []
        }) {
            TorrentListing(torrents: $0)
        }
    }

    /// Split by provider and fetched concurrently, each account in its own way (RD one `info` per
    /// torrent with bounded fan-out, TorBox one list call). Results come back in input order. A
    /// torrent of an account that is not signed in is skipped, like any other failed lookup.
    public func allTorrentInfos(from list: [Torrent]) async throws -> [TorrentInfo] {
        guard !list.isEmpty else { return [] }
        let byProvider = Dictionary(grouping: list) { DebridProvider.of(torrentID: $0.id) }
        let infos = try await withThrowingTaskGroup(of: [TorrentInfo].self) { group in
            for (provider, torrents) in byProvider {
                guard let client = client(for: provider) else { continue }
                group.addTask { try await client.allTorrentInfos(from: torrents) }
            }
            var all: [TorrentInfo] = []
            for try await batch in group { all += batch }
            return all
        }
        let byID = Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return list.compactMap { byID[$0.id] }
    }

    // MARK: - One torrent or link

    public func info(id: String) async throws -> TorrentInfo {
        try await routed(.of(torrentID: id)).info(id: id)
    }

    public func unrestrict(link: String) async throws -> UnrestrictedLink {
        try await routed(.of(link: link)).unrestrict(link: link)
    }

    public func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? {
        try await routed(.of(torrentID: info.id)).playableURL(for: info)
    }

    public func deleteTorrent(id: String) async throws {
        try await routed(.of(torrentID: id)).deleteTorrent(id: id)
    }

    // MARK: - Add

    public func add(magnetHash: String) async throws -> TorrentInfo {
        try await routed(addTarget).add(magnetHash: magnetHash)
    }

    public func addForDownload(magnetHash: String) async throws -> TorrentInfo {
        try await routed(addTarget).addForDownload(magnetHash: magnetHash)
    }

    // MARK: - Fan-out

    private struct Answer<T: Sendable>: Sendable {
        let provider: DebridProvider
        let result: Result<T, any Error>
    }

    /// Runs `call` on every account concurrently and returns each outcome in client order.
    private func eachClient<T: Sendable>(
        _ call: @escaping @Sendable (any DebridClient) async throws -> T
    ) async -> [Answer<T>] {
        await withTaskGroup(of: (Int, Answer<T>).self) { group in
            for (index, client) in clients.enumerated() {
                group.addTask {
                    do { return (index, Answer(provider: client.provider, result: .success(try await call(client)))) }
                    catch { return (index, Answer(provider: client.provider, result: .failure(error))) }
                }
            }
            var answers: [(Int, Answer<T>)] = []
            for await answer in group { answers.append(answer) }
            return answers.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// The accounts that answered, concatenated, with the failed ones named. Throws the first
    /// account's error only when none answered.
    private static func partial<T>(_ answers: [Answer<T>],
                                   listing: (T) -> TorrentListing) throws -> TorrentListing {
        var listed: [Torrent] = []
        var unavailable: Set<DebridProvider> = []
        var failures = 0
        var firstError: (any Error)?
        for answer in answers {
            switch answer.result {
            case .success(let value):
                let page = listing(value)
                listed += page.torrents
                unavailable.formUnion(page.unavailable)
            case .failure(let error):
                unavailable.insert(answer.provider)
                failures += 1
                if firstError == nil { firstError = error }
            }
        }
        if failures == answers.count, let firstError { throw firstError }
        return TorrentListing(torrents: listed, unavailable: unavailable)
    }
}
