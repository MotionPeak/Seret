import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One open file: answers libvlc's range reads from RAM, the disk index, or Real-Debrid.
///
/// Every fetch event wakes every waiting read, and each read re-plans from scratch. That is simple
/// enough to be obviously right, and cheap at this scale (a few waiters, a few hundred events/s).
///
/// RD failing for a while — the network dropping, RD answering 503 — costs a wait, never the
/// session: reads pause and ask again (`clearToFetch(_:)`), and only RD's "no" is final.
actor StreamSession {
    let id: UUID
    let fileKey: String
    private var upstream: URL
    private let refreshUpstream: @Sendable () async throws -> URL
    private let budget: StreamCacheBudget
    private let planner: FetchPlanner
    private let index: IndexStore
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private let retry: StreamRetryPolicy
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
    /// The link refresh in flight. Every fetch RD refuses while it runs waits for its result
    /// rather than asking for another — see `linkRefreshed(since:)`.
    private var refresh: Task<Bool, Never>?
    /// Which link `upstream` is: bumped by each refresh, and remembered by each fetch.
    private var linkGeneration = 0
    private var closed = false

    /// RD's "no" to this file: a 4xx no link refresh fixed, or a range it keeps ignoring. Final —
    /// a read that needs RD throws it at once, since asking again only repeats the answer.
    private var refusal: StreamError?
    /// RD failing for now: the network is down, RD answers 503. Never final — reads wait it out
    /// and ask again — and gone with the next byte RD sends.
    private var outage: Outage?

    /// Why RD is not serving this file, if it is not: its refusal, or a failure it is still in.
    /// libvlc sees either as a closed connection — an EOF — so without this the player cannot
    /// tell them from the end of the film; it asks when libvlc reports the end. An outage counts
    /// before any read gives up on it: libvlc may end first, and an outage taken for the end of
    /// the film would be recorded as finished. It matters most when the head came from disk:
    /// frames render before RD is ever asked.
    var upstreamFailure: StreamError? { refusal ?? outage?.latest }

    private(set) var upstreamRequestCount = 0
    /// How many times a fetch has been paused (tests and diagnostics).
    private(set) var suspendCount = 0
    var suspendedFetchCount: Int { fetches.values.filter(\.suspended).count }

    private struct ActiveFetch {
        let fetcher: UpstreamFetcher
        let start: Int64
        /// The `linkGeneration` it was started on.
        let link: Int
        var position: Int64
        var suspended = false
        /// Whether RD has sent it a byte. One that ends without any has failed, however it ended.
        var received = false
        /// The end of the latest read served from this fetch's bytes: where ITS reader is. libvlc
        /// reads with more than one connection at once (the header and the keyframe index at open),
        /// so read-ahead must be measured per reader — against one global "last read", each
        /// reader's fetch looked far ahead of the other and paused on every piece.
        var anchor: Int64?
        var readerPosition: Int64 { anchor ?? start }
    }

    /// RD failing, since the last byte it sent.
    private struct Outage {
        /// The latest failure: what a read that gives up throws, and what the player is told.
        var latest: StreamError
        /// Fetches failed in a row. Each pause before asking again is longer.
        var failures = 0
        /// Of those, whole files answered to range requests.
        var wholeFileAnswers = 0
        /// No fetch starts before this.
        var retryAt: ContinuousClock.Instant
    }

    /// One caller's — a read's, or the head's — account of the fetches it started.
    private struct Patience {
        var starts = 0
        var lastStart: ContinuousClock.Instant?
        /// When it stops waiting for an RD that keeps failing: `retry.budget` after it first found
        /// RD failing. One budget per read — another fetch's bytes ending the outage meanwhile do
        /// not hand a read whose own fetches keep failing a fresh one.
        var giveUpAt: ContinuousClock.Instant?

        mutating func started() {
            starts += 1
            lastStart = .now
        }
    }

    /// Fetches one read starts back to back; the ones after are paced. Other readers' planning can
    /// cancel a read's fetches over and over, and that churn — no fault of RD's, so never counted
    /// as a failure — must not ask RD for connections as fast as it spins.
    private static let maxFetchesPerRead = 4

    init(id: UUID, fileKey: String, upstream: URL,
         refreshUpstream: @escaping @Sendable () async throws -> URL,
         budget: StreamCacheBudget, index: IndexStore,
         makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration,
         retry: StreamRetryPolicy = .standard,
         log: @escaping @Sendable (String) -> Void) {
        self.id = id
        self.fileKey = fileKey
        self.upstream = upstream
        self.refreshUpstream = refreshUpstream
        self.budget = budget
        self.planner = FetchPlanner(budget: budget)
        self.index = index
        self.makeConfiguration = makeConfiguration
        self.retry = retry
        self.log = log
        self.cache = ChunkCache(chunkSize: budget.chunkSize, budget: budget.ramBytes)
    }

    // MARK: - Reading

    /// The file's size and type: from the disk index when it was opened before, else from RD.
    func head() async throws -> (total: Int64, contentType: String) {
        await loadIndexIfNeeded()
        var patience = Patience()
        while true {
            if closed { throw StreamError.closed }
            if let totalSize { return (totalSize, contentType) }
            if let refusal { throw refusal }
            if fetches.isEmpty {
                guard try await clearToFetch(&patience) else { continue }
                patience.started()
                startFetch(at: 0)
            }
            try await waitForProgress()
        }
    }

    /// At least one byte at `offset` (up to `max`, never crossing a chunk).
    func read(offset: Int64, max: Int) async throws -> Data {
        await loadIndexIfNeeded()
        var patience = Patience()
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
                // RD has refused this file: asking again only repeats the refusal.
                if let refusal { throw refusal }
                guard try await clearToFetch(&patience) else { continue }
                patience.started()
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
        fetches[id] = ActiveFetch(fetcher: fetcher, start: start, link: linkGeneration, position: start)
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
            if (200...299).contains(status) && !(status == 200 && fetch.start > 0) {
                if let total { await learnSize(total) }
                if let type { contentType = type }
            } else if [403, 404, 410].contains(status) {
                let refreshed = await linkRefreshed(since: fetch.link)
                // The refresh is an RD call the viewer can outlast: if the session closed or this
                // fetch was cancelled meanwhile, a new fetch would download for no one.
                guard !closed, fetches[id] != nil else { return }
                guard refreshed else { return refuse(.upstreamStatus(status), fetch: id) }
                cancelFetch(id)
                startFetch(at: fetch.start)                      // same bytes, fresh link
            } else if (400...499).contains(status), ![408, 425, 429].contains(status) {
                // About the file or the request (451 blocked, 416 past its end): RD would say it again.
                return refuse(.upstreamStatus(status), fetch: id)
            } else if status == 200 {
                // The whole file, answered to a range: not the bytes asked for. One bad server may
                // pass; RD ignoring the range for this file every time will not.
                let failure = StreamError.transport("RD answered a range request with the whole file")
                if (outage?.wholeFileAnswers ?? 0) + 1 >= retry.wholeFileAnswers {
                    return refuse(failure, fetch: id)
                }
                noteFailure(failure, fetch: id, wholeFile: true)
                return cancelFetch(id)
            } else {
                // "Not now" rather than "no": RD busy (429), a server fault (5xx), a timeout (408).
                noteFailure(.upstreamStatus(status), fetch: id)
                return cancelFetch(id)
            }
        case .data(let data):
            if outage != nil {
                outage = nil
                log("fetch #\(id): RD is sending again")
            }
            fetch.received = true
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
            if !fetch.received {
                // Over without a byte: a failed attempt, however it ended. Offline, every fetch
                // fails the instant it starts — counted, the next one waits instead of bursting.
                noteFailure(error ?? .transport("RD closed the connection before sending anything"),
                            fetch: id)
            } else if let error {
                log("fetch #\(id) ended: \(error)")
            }
        }
        wakeWaiters()
    }

    /// RD said no for good: from now on a read that needs RD throws `failure`. Everyone waiting
    /// re-plans — a read a fetch in flight will reach keeps waiting for it; the rest throw.
    private func refuse(_ failure: StreamError, fetch id: Int) {
        log("fetch #\(id) refused: \(failure)")
        refusal = failure
        cancelFetch(id)
    }

    /// A fetch failed with RD still worth asking: count it, and hold the next start back for a
    /// pause that grows with each failure in a row.
    private func noteFailure(_ failure: StreamError, fetch id: Int, wholeFile: Bool = false) {
        var outage = self.outage ?? Outage(latest: failure, retryAt: .now)
        outage.latest = failure
        outage.failures += 1
        if wholeFile { outage.wholeFileAnswers += 1 }
        let pause = retry.delay(afterFailures: outage.failures)
        outage.retryAt = .now + pause
        self.outage = outage
        log("fetch #\(id) failed (\(failure)), \(outage.failures) in a row: next try in \(pause)")
    }

    /// Whether this caller may start a fetch now. While RD is failing it waits out the pause, and
    /// once RD has failed it for `retry.budget` it gives up, throwing the latest failure — which
    /// nothing latches: the next read asks again, and finds RD back if the network is. Returns
    /// false after a wait: the caller re-plans, since anything may have changed meanwhile.
    /// Closing the session or cancelling the caller ends the wait at once.
    private func clearToFetch(_ patience: inout Patience) async throws -> Bool {
        try Task.checkCancellation()
        let now = ContinuousClock.now
        var notBefore = now
        if let outage {
            let giveUpAt = patience.giveUpAt ?? now + retry.budget
            patience.giveUpAt = giveUpAt
            guard now < giveUpAt else {
                log("gave up after \(retry.budget) of RD failing: \(outage.latest)")
                throw outage.latest
            }
            notBefore = min(outage.retryAt, giveUpAt)
        }
        if patience.starts >= Self.maxFetchesPerRead, let last = patience.lastStart {
            let pause = retry.delay(afterFailures: patience.starts - Self.maxFetchesPerRead + 1)
            notBefore = max(notBefore, last + pause)
        }
        guard notBefore > now else { return true }
        try await waitForProgress(until: notBefore)
        return false
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

    /// Whether a fetch refused on link `generation` has a newer link to try: one a refresh got
    /// since that fetch started, the one the refresh in flight gets, or one a new refresh gets.
    ///
    /// An expired link is refused on EVERY fetch, and fetches start in twos — a read and its
    /// look-behind, or two of libvlc's readers — so refusals arrive together. The second used to
    /// find the first's refresh begun, be denied one of its own, and fail its reads with 403 for
    /// good — while the refresh succeeded. Now it waits for that refresh, and a refusal of a
    /// link already replaced just moves to the current one.
    ///
    /// A link refused within a minute of the refresh that fetched it is refused for real: asking
    /// RD for yet another would only repeat the answer.
    private func linkRefreshed(since generation: Int) async -> Bool {
        if linkGeneration > generation { return true }
        if refresh == nil {
            if let at = refreshedAt, at.duration(to: .now) < .seconds(60) { return false }
            refreshedAt = .now
            refresh = Task { await installFreshLink() }
        }
        return await refresh?.value ?? false
    }

    private func installFreshLink() async -> Bool {
        defer { refresh = nil }
        guard let fresh = try? await refreshUpstream() else {
            log("upstream link refresh failed")
            return false
        }
        upstream = fresh
        linkGeneration += 1
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

    /// Until a fetch event, the session's close, the caller's cancellation — or `deadline`.
    private func waitForProgress(until deadline: ContinuousClock.Instant? = nil) async throws {
        let token = UUID()
        // Set up before the waiter is registered, but it cannot fire before: it needs this actor,
        // which nothing gives up until the continuation below is in place.
        let timer = deadline.map { deadline in
            Task { [weak self] in
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard !Task.isCancelled else { return }
                await self?.resumeWaiter(token)
            }
        }
        defer { timer?.cancel() }
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

    private func resumeWaiter(_ token: UUID) {
        waiters.removeValue(forKey: token)?.resume()
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
