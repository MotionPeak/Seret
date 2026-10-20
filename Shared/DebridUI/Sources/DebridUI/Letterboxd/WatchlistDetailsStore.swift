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
/// - **Two views of the same data.** `details` is progressive (published every `publishEvery`
///   films) — for the header, which describes one film and should complete as soon as it can.
///   `settled` changes only when a fetch pass is over — for the ROWS: building them from a
///   half-filled map re-sorted Highest Rated, re-ranked and cut the genre rows, and slid new films
///   in under the focused poster on every batch of a first visit. A pass is over when the queue
///   has drained, or — so one hung request cannot hold the rows back — `stragglerGrace` after the
///   queue emptied with requests still in flight.
/// - **Persisted** next to the watchlist mirror (`WritableStorage`, which proves the directory by
///   creating it — tvOS has no Application Support). Later visits draw at once (`settled` is read
///   from disk too). A film is fetched again once it is older than `maxAge` give or take up to
///   five days (fixed per film, so a list fetched in one go does not go stale in one go); the old
///   copy stays on screen meanwhile.
/// - A film whose fetch fails is left out, and asked again by a later `ensure` once
///   `retryAfter` has passed. Only a success is permanent.
@MainActor
@Observable
public final class WatchlistDetailsStore {
    public typealias Fetching = @Sendable (_ tmdbID: Int) async throws -> WatchlistFilmDetails

    /// Every film's details known so far, by TMDB id — updated as batches land.
    public private(set) var details: [Int: WatchlistFilmDetails]
    /// The details as of the last finished pass — what rows are built from.
    public private(set) var settled: [Int: WatchlistFilmDetails]
    /// Bumped on every publish of `details`, so a view can follow changes to it cheaply.
    public private(set) var generation = 0

    @ObservationIgnored private let fetch: Fetching
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let maxAge: TimeInterval
    @ObservationIgnored private let concurrency: Int
    @ObservationIgnored private let publishEvery: Int
    @ObservationIgnored private let retryAfter: TimeInterval
    @ObservationIgnored private let stragglerGrace: Duration

    /// Films waiting for a fetch, in the order they will go.
    @ObservationIgnored private var queue: [Int] = []
    /// Queued or being fetched — so an id is never asked twice at once.
    @ObservationIgnored private var pending: Set<Int> = []
    /// When each failed film last failed. Cleared by a success.
    @ObservationIgnored private var failedAt: [Int: Date] = [:]
    /// Results not yet published.
    @ObservationIgnored private var buffer: [Int: WatchlistFilmDetails] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// The pass a straggler timer belongs to, so a late timer from an old pass does nothing.
    @ObservationIgnored private var pass = 0

    /// The maximum jitter on `maxAge`, either way.
    public static let ageJitter: TimeInterval = 5 * 86_400

    public init(fileURL: URL?,
                now: @escaping @Sendable () -> Date = { Date() },
                maxAge: TimeInterval = 30 * 86_400,
                concurrency: Int = 6,
                publishEvery: Int = 24,
                retryAfter: TimeInterval = 15 * 60,
                stragglerGrace: Duration = .seconds(30),
                fetch: @escaping Fetching) {
        self.fileURL = fileURL
        self.now = now
        self.maxAge = maxAge
        self.concurrency = max(1, concurrency)
        self.publishEvery = max(1, publishEvery)
        self.retryAfter = retryAfter
        self.stragglerGrace = stragglerGrace
        self.fetch = fetch
        let stored = Self.read(fileURL)
        self.details = stored
        self.settled = stored
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

    /// A film's own shift of `maxAge`, within ±`ageJitter`. Derived from its id, so it is the same
    /// on every launch and device.
    public static func ageJitter(for tmdbID: Int) -> TimeInterval {
        let bucket = Int((UInt64(truncatingIfNeeded: tmdbID) &* 2_654_435_761) % 11) - 5   // -5…5
        return TimeInterval(bucket) * 86_400
    }

    /// Makes sure every film in `ids` has details: missing ones first (in the order given), then
    /// stale ones. Returns when the store's worker has finished — including films other callers
    /// asked for meanwhile.
    public func ensure(_ ids: [Int]) async {
        let now = now()
        var missing: [Int] = []
        var stale: [Int] = []
        var seen = Set<Int>()
        for id in ids where seen.insert(id).inserted && !pending.contains(id) {
            if let failed = failedAt[id], now.timeIntervalSince(failed) < retryAfter { continue }
            if let known = details[id] {
                let age = maxAge + Self.ageJitter(for: id)
                if now.timeIntervalSince(known.fetchedAt) > age { stale.append(id) }
            } else {
                missing.append(id)
            }
        }
        let added = missing + stale
        queue.append(contentsOf: added)
        pending.formUnion(added)

        if worker == nil, !queue.isEmpty {
            pass += 1
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
        let thisPass = pass
        var stragglerTimer: Task<Void, Never>?
        await withTaskGroup(of: (Int, WatchlistFilmDetails?).self) { group in
            var running = 0
            var sincePublish = 0
            while true {
                while running < concurrency, !queue.isEmpty {
                    let id = queue.removeFirst()
                    group.addTask { (id, try? await fetch(id)) }
                    running += 1
                }
                // Everything is dispatched; only in-flight requests remain. Give them a grace
                // period, then let the rows have what has landed.
                if queue.isEmpty, running > 0, stragglerTimer == nil {
                    let grace = stragglerGrace
                    stragglerTimer = Task { [weak self] in
                        try? await Task.sleep(for: grace)
                        guard !Task.isCancelled else { return }
                        self?.settle(ifPass: thisPass)
                    }
                }
                if !queue.isEmpty { stragglerTimer?.cancel(); stragglerTimer = nil }
                guard let (id, result) = await group.next() else { break }
                running -= 1
                pending.remove(id)
                if let result {
                    buffer[id] = result
                    failedAt[id] = nil
                } else {
                    failedAt[id] = now()
                }
                sincePublish += 1
                if sincePublish >= publishEvery {
                    sincePublish = 0
                    publish()
                }
            }
        }
        stragglerTimer?.cancel()
        settle(ifPass: thisPass)
    }

    /// The pass is over (or its stragglers have had their grace): publish what is buffered and
    /// hand the rows the whole map in one change.
    private func settle(ifPass expected: Int) {
        guard expected == pass else { return }
        publish()
        if settled != details { settled = details }
    }

    /// One observable change for the whole batch, then the file.
    private func publish() {
        guard !buffer.isEmpty else { return }
        details.merge(buffer) { _, new in new }
        buffer = [:]
        generation &+= 1
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
