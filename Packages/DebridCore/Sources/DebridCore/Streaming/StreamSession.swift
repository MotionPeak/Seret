import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One open file: answers libvlc's range reads from RAM, the disk index, or Real-Debrid.
///
/// Every fetch event wakes every waiting read, and each read re-plans from scratch. That is simple
/// enough to be obviously right, and cheap at this scale (a few waiters, a few hundred events/s).
actor StreamSession {
    let id: UUID
    let fileKey: String
    private var upstream: URL
    private let refreshUpstream: @Sendable () async throws -> URL
    private let budget: StreamCacheBudget
    private let planner: FetchPlanner
    private let index: IndexStore
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private let log: @Sendable (String) -> Void

    private var cache: ChunkCache
    private var totalSize: Int64?
    private var contentType = "application/octet-stream"
    private var indexed: Set<Int> = []
    private var indexLoaded = false
    private var fetches: [Int: ActiveFetch] = [:]
    private var nextFetchID = 0
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var lastReadEnd: Int64?
    private var playbackStarted = false
    private var headReads: [Int] = []
    private var refreshedAt: ContinuousClock.Instant?
    private var headFailure: StreamError?
    private var closed = false

    private(set) var upstreamRequestCount = 0
    var suspendedFetchCount: Int { fetches.values.filter(\.suspended).count }

    private struct ActiveFetch {
        let fetcher: UpstreamFetcher
        let start: Int64
        var position: Int64
        var suspended = false
        var responded = false
    }

    /// Starts per read before it gives up: a link that keeps failing must not hammer RD forever.
    private static let maxFetchesPerRead = 4

    init(id: UUID, fileKey: String, upstream: URL,
         refreshUpstream: @escaping @Sendable () async throws -> URL,
         budget: StreamCacheBudget, index: IndexStore,
         makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration,
         log: @escaping @Sendable (String) -> Void) {
        self.id = id
        self.fileKey = fileKey
        self.upstream = upstream
        self.refreshUpstream = refreshUpstream
        self.budget = budget
        self.planner = FetchPlanner(budget: budget)
        self.index = index
        self.makeConfiguration = makeConfiguration
        self.log = log
        self.cache = ChunkCache(chunkSize: budget.chunkSize, budget: budget.ramBytes)
    }

    // MARK: - Reading

    /// The file's size and type: from the disk index when it was opened before, else from RD.
    func head() async throws -> (total: Int64, contentType: String) {
        await loadIndexIfNeeded()
        var starts = 0
        while true {
            if closed { throw StreamError.closed }
            if let headFailure { throw headFailure }
            if let totalSize { return (totalSize, contentType) }
            if fetches.isEmpty {
                starts += 1
                guard starts <= Self.maxFetchesPerRead else { throw StreamError.transport("no response") }
                startFetch(at: 0)
            }
            try await waitForProgress()
        }
    }

    /// At least one byte at `offset` (up to `max`, never crossing a chunk).
    func read(offset: Int64, max: Int) async throws -> Data {
        await loadIndexIfNeeded()
        var starts = 0
        while true {
            if closed { throw StreamError.closed }
            if let totalSize, offset >= totalSize { throw StreamError.endOfFile }
            if let data = cache.read(at: offset, max: max) {
                noteRead(offset: offset, count: data.count)
                return data
            }
            let chunk = cache.chunkIndex(of: offset)
            let decision = planner.decide(
                offset: offset, cached: false, inIndex: indexed.contains(chunk),
                fetches: fetches.map { FetchSnapshot(id: $0.key, position: $0.value.position) },
                lastRead: lastReadEnd,
                isChunkCached: { self.cache.contains($0) || self.indexed.contains($0) })
            switch decision {
            case .serve:
                continue
            case .loadFromIndex:
                if let data = await index.loadChunk(fileKey: fileKey, index: chunk) {
                    if !cache.contains(chunk) { cache.insert(data, index: chunk) }
                } else {
                    indexed.remove(chunk)                    // gone from disk: fetch it instead
                }
            case .wait(let id):
                if fetches[id]?.suspended == true { resumeFetch(id) }
                try await waitForProgress()
            case .fetch(let start, let lookBehind, let cancel):
                starts += 1
                guard starts <= Self.maxFetchesPerRead else {
                    throw StreamError.transport("RD kept failing at \(offset)")
                }
                for id in cancel { cancelFetch(id) }
                startFetch(at: start)
                if let lookBehind { startFetch(at: lookBehind) }
                try await waitForProgress()
            }
        }
    }

    // MARK: - Fetches

    private func startFetch(at start: Int64) {
        let id = nextFetchID
        nextFetchID += 1
        upstreamRequestCount += 1
        let fetcher = UpstreamFetcher(url: upstream, start: start, configuration: makeConfiguration())
        fetches[id] = ActiveFetch(fetcher: fetcher, start: start, position: start)
        log("fetch #\(id) from \(start)")
        Task { [weak self] in
            for await event in fetcher.events { await self?.handle(event, from: id) }
        }
        fetcher.start()
    }

    private func handle(_ event: UpstreamFetcher.Event, from id: Int) async {
        guard var fetch = fetches[id] else { return }            // cancelled
        switch event {
        case .response(let status, let total, let type):
            fetch.responded = true
            fetches[id] = fetch
            let usable = (200...299).contains(status) && !(status == 200 && fetch.start > 0)
            if usable {
                if let total { await learnSize(total) }
                if let type { contentType = type }
            } else if [403, 404, 410].contains(status), await refreshUpstreamOnce() {
                cancelFetch(id)
                startFetch(at: fetch.start)                      // same bytes, fresh link
            } else {
                log("fetch #\(id) refused: \(status)")
                cancelFetch(id)
                if totalSize == nil { headFailure = .upstreamStatus(status) }
                wakeWaiters(throwing: StreamError.upstreamStatus(status))
                return
            }
        case .data(let data):
            let result = cache.append(data, at: fetch.position)
            fetch.position += Int64(result.accepted)
            fetches[id] = fetch
            cache.evictToBudget()
            if result.hitCached {
                cancelFetch(id)                                  // the rest is already here
            } else if !fetch.suspended,
                      planner.shouldSuspend(position: fetch.position,
                                            lastReadEnd: lastReadEnd ?? fetch.start)
                        || cache.byteCount > budget.ramBytes {
                fetch.suspended = true
                fetches[id] = fetch
                fetch.fetcher.suspend()
            }
        case .finished(let error):
            fetches.removeValue(forKey: id)
            if let error {
                log("fetch #\(id) ended: \(error)")
                if totalSize == nil, !fetch.responded { headFailure = error }
            }
        }
        wakeWaiters()
    }

    private func cancelFetch(_ id: Int) {
        guard let fetch = fetches.removeValue(forKey: id) else { return }
        fetch.fetcher.cancel()
        wakeWaiters()                                            // anyone waiting on it re-plans
    }

    private func resumeFetch(_ id: Int) {
        guard fetches[id]?.suspended == true else { return }
        fetches[id]?.suspended = false
        fetches[id]?.fetcher.resume()
    }

    private func learnSize(_ total: Int64) async {
        if let known = totalSize, known != total {
            log("size changed \(known) → \(total): discarding the stored index")
            await index.discard(fileKey: fileKey)
            indexed = []
        }
        totalSize = total
        cache.setTotalSize(total)
    }

    private func refreshUpstreamOnce() async -> Bool {
        if let at = refreshedAt, at.duration(to: .now) < .seconds(60) { return false }
        refreshedAt = .now
        guard let fresh = try? await refreshUpstream() else { return false }
        upstream = fresh
        log("upstream link refreshed")
        return true
    }

    private func noteRead(offset: Int64, count: Int) {
        let end = offset + Int64(count)
        lastReadEnd = end
        if !playbackStarted {
            let chunk = cache.chunkIndex(of: offset)
            if !headReads.contains(chunk) { headReads.append(chunk) }
        }
        for (id, fetch) in fetches
        where fetch.suspended && planner.shouldResume(position: fetch.position, lastReadEnd: end) {
            resumeFetch(id)
        }
    }

    // MARK: - Waiting

    private func waitForProgress() async throws {
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[token] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(token) }
        }
    }

    private func cancelWaiter(_ token: UUID) {
        waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
    }

    private func wakeWaiters(throwing error: Error? = nil) {
        let all = waiters
        waiters = [:]
        for continuation in all.values {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }

    // MARK: - Lifecycle (persistence lands in Task 7)

    func markPlaybackStarted() async {
        playbackStarted = true
    }

    func close() async {
        guard !closed else { return }
        closed = true
        for id in Array(fetches.keys) { cancelFetch(id) }
        wakeWaiters(throwing: StreamError.closed)
    }

    func trimMemory() {
        cache.dropHistory()
    }

    private func loadIndexIfNeeded() async {
        guard !indexLoaded else { return }
        indexLoaded = true
        guard let entry = await index.open(fileKey: fileKey) else { return }
        if totalSize == nil {
            totalSize = entry.totalSize
            cache.setTotalSize(entry.totalSize)
        }
        indexed = entry.chunks
    }
}
