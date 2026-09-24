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
    /// How many times a fetch has been paused (tests and diagnostics).
    private(set) var suspendCount = 0
    var suspendedFetchCount: Int { fetches.values.filter(\.suspended).count }

    private struct ActiveFetch {
        let fetcher: UpstreamFetcher
        let start: Int64
        var position: Int64
        var suspended = false
        var responded = false
        /// The end of the latest read served from this fetch's bytes: where ITS reader is. libvlc
        /// reads with more than one connection at once (the header and the keyframe index at open),
        /// so read-ahead must be measured per reader — against one global "last read", each
        /// reader's fetch looked far ahead of the other and paused on every piece.
        var anchor: Int64?
        var readerPosition: Int64 { anchor ?? start }
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
                startFetch(at: cache.fetchStart(for: start))
                if let lookBehind { startFetch(at: cache.fetchStart(for: lookBehind)) }
                try await waitForProgress()
            }
        }
    }

    // MARK: - Fetches

    private func startFetch(at start: Int64) {
        guard !closed else { return }                            // nobody would read or pause it
        let id = nextFetchID
        nextFetchID += 1
        upstreamRequestCount += 1
        let fetcher = UpstreamFetcher(url: upstream, start: start, configuration: makeConfiguration())
        fetches[id] = ActiveFetch(fetcher: fetcher, start: start, position: start)
        log("fetch #\(id) from \(start)")
        Task { [weak self] in
            for await event in fetcher.events {
                guard let self else { fetcher.cancel(); return }  // session gone: stop downloading
                await self.handle(event, from: id)
            }
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
                // The refresh is an RD call the viewer can outlast: if the session closed or this
                // fetch was cancelled meanwhile, a new fetch would download for no one.
                guard !closed, fetches[id] != nil else { return }
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
            cache.evictToBudget(anchor: lastReadEnd ?? fetch.start, protecting: protectedRanges())
            if result.hitCached {
                cancelFetch(id)                                  // the rest is already here
            } else if !fetch.suspended,
                      planner.shouldSuspend(position: fetch.position, lastReadEnd: fetch.readerPosition)
                        || cache.byteCount > budget.ramBytes {
                fetch.suspended = true
                fetches[id] = fetch
                fetch.fetcher.suspend()
                suspendCount += 1
                log("fetch #\(id) paused at \(fetch.position) (reads at \(fetch.readerPosition), "
                    + "ram \(cache.byteCount >> 20) MiB, unread \(cache.unreadBytes >> 20) MiB)")
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
        log("fetch #\(id) resumed (reads at \(fetches[id]?.readerPosition ?? -1), "
            + "ram \(cache.byteCount >> 20) MiB)")
    }

    /// What eviction must not touch: each fetch's unread bytes in front of its reader, and the
    /// read-ahead window in front of the latest read.
    private func protectedRanges() -> [Range<Int64>] {
        var ranges = fetches.values.map { $0.readerPosition..<max($0.readerPosition, $0.position) }
        if let lastReadEnd { ranges.append(lastReadEnd..<(lastReadEnd + Int64(budget.readAheadBytes))) }
        return ranges
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
        // The read lands in a fetch's streamed range: that fetch's reader has moved.
        for (id, fetch) in fetches where fetch.start <= offset && offset <= fetch.position {
            fetches[id]?.anchor = max(fetch.anchor ?? 0, end)
        }
        for (id, fetch) in fetches
        where fetch.suspended
            && planner.shouldResume(position: fetch.position, lastReadEnd: fetch.readerPosition) {
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

    // MARK: - Lifecycle

    /// The first frame is on screen. Everything read until now — the header, the keyframe index,
    /// the resume point's region — is what the next open of this file will read first, so it goes
    /// to disk now, while it is certainly still in RAM.
    func markPlaybackStarted() async {
        guard !playbackStarted else { return }
        playbackStarted = true
        guard let totalSize else { return }
        let limit = budget.indexHeadBytesPerFile / budget.chunkSize
        let chunks = headReads.prefix(limit).compactMap { index in
            cache.completeData(index).map { (index, $0) }
        }
        await index.saveHead(fileKey: fileKey, totalSize: totalSize, chunks: chunks)
        indexed.formUnion(chunks.map(\.0))
        log("kept \(chunks.count) head chunks for the next open")
    }

    /// Stop fetching, release waiting reads, and keep the region around the last read — where the
    /// next resume will land, including the keyframe before it.
    func close() async {
        guard !closed else { return }
        closed = true
        for id in Array(fetches.keys) { cancelFetch(id) }
        wakeWaiters(throwing: StreamError.closed)
        guard let totalSize, let last = lastReadEnd, last > 0 else { return }
        let size = Int64(budget.chunkSize)
        let from = max(0, last - Int64(budget.resumeBehindBytes))
        let to = min(totalSize, last + Int64(budget.resumeAheadBytes))
        guard to > from else { return }
        let chunks = (Int(from / size)...Int((to - 1) / size)).compactMap { index in
            cache.completeData(index).map { (index, $0) }
        }
        await index.saveResume(fileKey: fileKey, totalSize: totalSize, chunks: chunks)
        log("kept \(chunks.count) resume chunks around \(last)")
    }

    func trimMemory() {
        cache.dropOutsideWindow(anchor: lastReadEnd ?? 0, protecting: protectedRanges())
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
