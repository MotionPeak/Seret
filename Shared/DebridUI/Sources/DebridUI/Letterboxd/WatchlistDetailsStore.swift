import Foundation
import Observation
import DebridCore

/// TMDB details for every film on the watchlist, fetched once and kept on disk — the Apple TV
/// Watchlist page builds its genre, rating and runtime rows from them.
///
/// - **Store-owned loads.** `ensure` queues what is missing and joins ONE worker task the store
///   owns, so a caller that goes away (the page's `.task` cancelled) never cancels the fetch and a
///   second caller never starts a duplicate.
/// - **Capped.** At most `concurrency` details calls at once: a 250-film list must not fire 250
///   requests at TMDB.
/// - **Published in batches**, not per film — every publish re-runs the page's row building.
/// - **Persisted** next to the watchlist mirror (`WritableStorage`, which proves the directory by
///   creating it — tvOS has no Application Support). Later visits draw at once; films older than
///   `maxAge` are fetched again after the missing ones, and stay on screen meanwhile.
/// - A film whose fetch fails is left out and not asked again until the next launch.
@MainActor
@Observable
public final class WatchlistDetailsStore {
    public typealias Fetching = @Sendable (_ tmdbID: Int) async throws -> WatchlistFilmDetails

    /// Every film's details known so far, by TMDB id.
    public private(set) var details: [Int: WatchlistFilmDetails]

    @ObservationIgnored private let fetch: Fetching
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maxAge: TimeInterval
    @ObservationIgnored private let concurrency: Int
    @ObservationIgnored private let publishEvery: Int

    /// Films waiting for a fetch, in the order they will go.
    @ObservationIgnored private var queue: [Int] = []
    /// Queued or being fetched — so an id is never asked twice at once.
    @ObservationIgnored private var pending: Set<Int> = []
    /// Fetched (or failed) this session — never queued again until the next launch.
    @ObservationIgnored private var attempted: Set<Int> = []
    /// Results not yet published.
    @ObservationIgnored private var buffer: [Int: WatchlistFilmDetails] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?

    public init(fileURL: URL?,
                now: @escaping @Sendable () -> Date = { Date() },
                maxAge: TimeInterval = 30 * 86_400,
                concurrency: Int = 6,
                publishEvery: Int = 24,
                fetch: @escaping Fetching) {
        self.fileURL = fileURL
        self.now = now
        self.maxAge = maxAge
        self.concurrency = max(1, concurrency)
        self.publishEvery = max(1, publishEvery)
        self.fetch = fetch
        self.details = Self.read(fileURL)
    }

    /// Fetches TMDB movie details through the app's details provider.
    public convenience init(fileURL: URL?, details provider: MediaDetailsProviding,
                            now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(fileURL: fileURL, now: now) { id in
            WatchlistFilmDetails(movie: try await provider.movieDetails(tmdbID: id), fetchedAt: now())
        }
    }

    /// Beside the watchlist mirror, through the same storage helper.
    public static func defaultURL() -> URL? {
        WritableStorage.file(named: "letterboxd-watchlist-details.json")
    }

    /// Makes sure every film in `ids` has details: missing ones first (in the order given), then
    /// stale ones. Returns when the store's worker has finished — including films other callers
    /// asked for meanwhile.
    public func ensure(_ ids: [Int]) async {
        let cutoff = now().addingTimeInterval(-maxAge)
        var missing: [Int] = []
        var stale: [Int] = []
        var seen = Set<Int>()
        for id in ids where seen.insert(id).inserted
            && !pending.contains(id) && !attempted.contains(id) {
            if let known = details[id] {
                if known.fetchedAt < cutoff { stale.append(id) }
            } else {
                missing.append(id)
            }
        }
        let added = missing + stale
        queue.append(contentsOf: added)
        pending.formUnion(added)

        if worker == nil, !queue.isEmpty {
            worker = Task { [weak self] in
                await self?.drain()
                self?.worker = nil
            }
        }
        await worker?.value
    }

    /// Runs the queue to empty, `concurrency` at a time, picking up anything queued meanwhile.
    private func drain() async {
        let fetch = fetch
        await withTaskGroup(of: (Int, WatchlistFilmDetails?).self) { group in
            var running = 0
            var sincePublish = 0
            while true {
                while running < concurrency, !queue.isEmpty {
                    let id = queue.removeFirst()
                    group.addTask { (id, try? await fetch(id)) }
                    running += 1
                }
                guard let (id, result) = await group.next() else { break }
                running -= 1
                pending.remove(id)
                attempted.insert(id)
                if let result { buffer[id] = result }
                sincePublish += 1
                if sincePublish >= publishEvery {
                    sincePublish = 0
                    publish()
                }
            }
        }
        publish()
    }

    /// One observable change for the whole batch, then the file.
    private func publish() {
        guard !buffer.isEmpty else { return }
        details.merge(buffer) { _, new in new }
        buffer = [:]
        Self.write(details, to: fileURL)
    }

    // MARK: - Disk

    private struct File: Codable {
        var version = 1
        var films: [WatchlistFilmDetails]
    }

    private static func read(_ url: URL?) -> [Int: WatchlistFilmDetails] {
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1
        else { return [:] }
        return Dictionary(file.films.map { ($0.tmdbID, $0) }, uniquingKeysWith: { _, last in last })
    }

    private static func write(_ details: [Int: WatchlistFilmDetails], to url: URL?) {
        guard let url else { return }
        let films = details.values.sorted { $0.tmdbID < $1.tmdbID }
        guard let data = try? JSONEncoder().encode(File(films: films)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
