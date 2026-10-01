import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private func tv(_ status: String, _ progress: Double = 0, id: String = "TID") -> TorrentInfo {
    TorrentInfo(id: id, filename: "M", hash: "h", bytes: 1, progress: progress, status: status,
                files: [TorrentFile(id: 1, path: "/M/m.mkv", bytes: 1, selected: 1)],
                links: ["https://rd/d/X"])
}

private func stream(_ hash: String) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t", parsed: ParsedRelease(title: "t", resolution: "1080p"),
                 languages: ["en"], sizeBytes: 1, sourceName: nil)
}

private final class FakeReq: DownloadRequesting, @unchecked Sendable {
    let perHash: [String: Result<TorrentInfo, FakeError>]
    let fallback: Result<TorrentInfo, FakeError>
    let throwsError: Error?
    init(_ fallback: Result<TorrentInfo, FakeError>, perHash: [String: Result<TorrentInfo, FakeError>] = [:],
         throwsError: Error? = nil) {
        self.fallback = fallback; self.perHash = perHash; self.throwsError = throwsError
    }
    func startDownload(infoHash: String) async throws -> TorrentInfo {
        if let throwsError { throw throwsError }
        return try (perHash[infoHash] ?? fallback).get()
    }
}

/// Per-hash outcomes consumed in order (the last one repeats), plus a log of what was asked — the
/// fallback ORDER is the behaviour under test, not just the final state.
private final class ScriptedReq: DownloadRequesting, @unchecked Sendable {
    private var outcomes: [String: [Result<TorrentInfo, Error>]]
    private(set) var calls: [String] = []
    init(_ outcomes: [String: [Result<TorrentInfo, Error>]]) { self.outcomes = outcomes }
    func startDownload(infoHash: String) async throws -> TorrentInfo {
        calls.append(infoHash)
        guard var queue = outcomes[infoHash], !queue.isEmpty else { throw FakeError.boom }
        let next = queue.removeFirst()
        outcomes[infoHash] = queue.isEmpty ? [next] : queue
        return try next.get()
    }
}

private final class FakeRecords: DownloadRecording, @unchecked Sendable {
    private(set) var upserts: [DownloadRequestData] = []
    private(set) var deleted: [String] = []
    var seeded: [DownloadRequestData]
    init(seeded: [DownloadRequestData] = []) { self.seeded = seeded }
    func upsert(_ data: DownloadRequestData) async throws { upserts.append(data) }
    /// What was there at launch plus what was written since — as the real store reads back.
    func all() async throws -> [DownloadRequestData] { seeded + upserts }
    func delete(torrentID: String) async throws { deleted.append(torrentID) }
}

private final class FakeDeleter: DownloadDeleting, @unchecked Sendable {
    private(set) var deleted: [String] = []
    func deleteTorrent(id: String) async throws { deleted.append(id) }
}

private final class FakePoller: DownloadPolling, @unchecked Sendable {
    var passes: [[DownloadStatus]]
    var shouldThrow = false
    init(_ passes: [[DownloadStatus]]) { self.passes = passes }
    func poll() async throws -> [DownloadStatus] {
        if shouldThrow { throw FakeError.boom }
        return passes.isEmpty ? [] : passes.removeFirst()
    }
}

/// Answers `first` once and nothing after, counting every poll.
private final class CountingPoller: DownloadPolling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [DownloadStatus]?
    private var _polls = 0
    var polls: Int { lock.withLock { _polls } }
    init(first: [DownloadStatus]) { pending = first }
    func poll() async throws -> [DownloadStatus] {
        lock.withLock {
            _polls += 1
            defer { pending = nil }
            return pending ?? []
        }
    }
}

@MainActor
@Suite struct DownloadStoreTests {
    private func make(req: any DownloadRequesting = FakeReq(.success(tv("queued"))),
                      records: FakeRecords = FakeRecords(),
                      poller: FakePoller = FakePoller([]),
                      deleter: FakeDeleter = FakeDeleter(),
                      onReady: @escaping (DownloadStatus) -> Void = { _ in },
                      maxAttempts: Int = 6) -> DownloadStore {
        DownloadStore(service: req, records: records, poller: poller, deleter: deleter,
                      onReady: { onReady($0) }, maxAttempts: maxAttempts)
    }

    @Test func cancelDeletesTorrentClearsRecordAndBadge() async {
        let records = FakeRecords()
        let deleter = FakeDeleter()
        let s = make(req: FakeReq(.success(tv("downloading", id: "TID"))), records: records, deleter: deleter)
        await s.request(contentKey: DownloadKey.movie(tmdbID: 5), tmdbID: 5, title: "X", kind: .movie, candidates: [stream("h")])
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 5)) != nil)
        await s.cancel(contentKey: DownloadKey.movie(tmdbID: 5))
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 5)) == nil)          // badge gone
        #expect(deleter.deleted == ["TID"])           // RD torrent removed
        #expect(records.deleted == ["TID"])           // persisted record removed
    }

    @Test func requestStartsDownloadAndRecordsIt() async {
        let records = FakeRecords()
        let s = make(req: FakeReq(.success(tv("queued", id: "TID"))), records: records)
        await s.request(contentKey: DownloadKey.movie(tmdbID: 42), tmdbID: 42, title: "Obsession", kind: .movie, candidates: [stream("h1")])
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 42))?.phase == .queued)
        #expect(records.upserts.count == 1)
        #expect(records.upserts.first?.torrentID == "TID")
        #expect(records.upserts.first?.infoHash == "h1")
        #expect(records.upserts.first?.tmdbID == 42)
    }

    /// A second press while the first download is starting or running added a SECOND torrent, and
    /// the one Home tile then alternated between the two progress values. A second press is the
    /// SAME request — the same ranked list, the same release first.
    @Test func aSecondPressOfTheSameReleaseStartsNothing() async {
        let req = ScriptedReq(["h1": [.success(tv("downloading", id: "T1")),
                                      .success(tv("downloading", id: "T1b"))]])
        let records = FakeRecords()
        let s = make(req: req, records: records)
        let key = DownloadKey.movie(tmdbID: 11)
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        #expect(req.calls == ["h1"])
        #expect(records.upserts.map(\.torrentID) == ["T1"])
    }

    /// …but a DIFFERENT release is the viewer replacing the download — "pick another version" on one
    /// stuck at 3%, a pasted magnet. That was ignored while reporting success. It now cancels the
    /// one under way and starts the one asked for.
    @Test func aDifferentReleaseReplacesTheOneUnderWay() async {
        let req = ScriptedReq(["h1": [.success(tv("downloading", id: "T1"))],
                               "h2": [.success(tv("downloading", id: "T2"))]])
        let records = FakeRecords()
        let deleter = FakeDeleter()
        let s = make(req: req, records: records, deleter: deleter)
        let key = DownloadKey.movie(tmdbID: 11)
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h2")])
        #expect(req.calls == ["h1", "h2"])
        #expect(deleter.deleted == ["T1"])
        #expect(s.status(forContentKey: key)?.torrentID == "T2")
    }

    /// Real-Debrid reports an uncached torrent with no seeders as converting a magnet — `.queued` —
    /// for as long as it is stuck, which is exactly the download a viewer replaces. Every `.queued`
    /// was taken for the store's own "still choosing a version" placeholder, so another version or
    /// a pasted magnet said it was sent and changed nothing.
    @Test func aDifferentReleaseReplacesOneRealDebridHasQueued() async {
        let req = ScriptedReq(["h1": [.success(tv("magnet_conversion", id: "T1"))],
                               "h2": [.success(tv("downloading", id: "T2"))]])
        let deleter = FakeDeleter()
        let s = make(req: req, deleter: deleter)
        let key = DownloadKey.movie(tmdbID: 11)
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        #expect(s.status(forContentKey: key)?.phase == .queued)
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h2")])
        #expect(req.calls == ["h1", "h2"])
        #expect(deleter.deleted == ["T1"])
        #expect(s.status(forContentKey: key)?.torrentID == "T2")
    }

    /// …and the same release pressed again while Real-Debrid has it queued is still just a second
    /// press.
    @Test func theSameReleasePressedAgainWhileQueuedStartsNothing() async {
        let req = ScriptedReq(["h1": [.success(tv("queued", id: "T1")), .success(tv("queued", id: "T1b"))]])
        let deleter = FakeDeleter()
        let s = make(req: req, deleter: deleter)
        let key = DownloadKey.movie(tmdbID: 11)
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        await s.request(contentKey: key, tmdbID: 11, title: "X", kind: .movie, candidates: [stream("h1")])
        #expect(req.calls == ["h1"])
        #expect(deleter.deleted.isEmpty)
    }

    @Test func requestFallsBackThroughCandidates() async {
        // First candidate is a dead magnet; second starts.
        let req = FakeReq(.failure(.boom), perHash: ["h2": .success(tv("downloading", id: "T2"))])
        let records = FakeRecords()
        let s = make(req: req, records: records)
        await s.request(contentKey: DownloadKey.movie(tmdbID: 7), tmdbID: 7, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 7))?.phase == .downloading)
        #expect(records.upserts.first?.infoHash == "h2")
    }

    @Test func requestBlockedByRDShowsCopyrightMessage() async {
        let s = make(req: FakeReq(.failure(.boom), throwsError: RDAddError.blocked))
        await s.request(contentKey: DownloadKey.movie(tmdbID: 9), tmdbID: 9, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        if case .failed(let msg) = s.status(forContentKey: DownloadKey.movie(tmdbID: 9))?.phase {
            #expect(msg.lowercased().contains("blocked") || msg.lowercased().contains("copyright"))
        } else { Issue.record("expected failed-blocked") }
    }

    @Test func requestWithNoCandidatesFails() async {
        let s = make()
        await s.request(contentKey: DownloadKey.movie(tmdbID: 1), tmdbID: 1, title: "X", kind: .movie, candidates: [])
        if case .failed = s.status(forContentKey: DownloadKey.movie(tmdbID: 1))?.phase {} else { Issue.record("expected failed") }
    }

    @Test func requestAllCandidatesFailMarksFailed() async {
        let s = make(req: FakeReq(.failure(.boom)))
        await s.request(contentKey: DownloadKey.movie(tmdbID: 2), tmdbID: 2, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        if case .failed = s.status(forContentKey: DownloadKey.movie(tmdbID: 2))?.phase {} else { Issue.record("expected failed") }
    }

    // MARK: - Copyright-blocked candidates

    private func failureMessage(_ s: DownloadStore, _ key: String) -> String? {
        if case .failed(let msg)? = s.status(forContentKey: key)?.phase { return msg }
        Issue.record("expected a failed status for \(key)")
        return nil
    }

    @Test func blockedCandidatesDoNotSpendAnAttempt() async {
        // Two refused as copyright-flagged, one dead, then a good one. With a budget of two REAL
        // attempts the good one must still be reached: a 451 is one request that creates nothing,
        // so it is not a turn.
        let req = ScriptedReq(["h1": [.failure(RDAddError.blocked)], "h2": [.failure(RDAddError.blocked)],
                               "h3": [.failure(FakeError.boom)], "h4": [.success(tv("queued", id: "T4"))]])
        let s = make(req: req, maxAttempts: 2)
        let key = DownloadKey.movie(tmdbID: 3)
        await s.request(contentKey: key, tmdbID: 3, title: "X", kind: .movie,
                        candidates: [stream("h1"), stream("h2"), stream("h3"), stream("h4")])
        #expect(req.calls == ["h1", "h2", "h3", "h4"])
        #expect(s.status(forContentKey: key)?.torrentID == "T4")
    }

    @Test func aBlockedVersionAmongFailuresDoesNotCondemnTheTitle() async {
        // One version is on RD's blocklist and the other simply failed to start. That is not
        // "none can be added" — the message must say which part is blocked and leave the rest open.
        let req = ScriptedReq(["h1": [.failure(RDAddError.blocked)], "h2": [.failure(FakeError.boom)]])
        let s = make(req: req)
        let key = DownloadKey.movie(tmdbID: 4)
        await s.request(contentKey: key, tmdbID: 4, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        guard let msg = failureMessage(s, key) else { return }
        #expect(msg.contains("1 version"))
        #expect(!msg.lowercased().contains("every version"))
        #expect(!msg.lowercased().contains("none can be added"))
    }

    @Test func everyVersionBlockedSaysSo() async {
        let req = ScriptedReq(["h1": [.failure(RDAddError.blocked)], "h2": [.failure(RDAddError.blocked)]])
        let s = make(req: req)
        let key = DownloadKey.movie(tmdbID: 5)
        await s.request(contentKey: key, tmdbID: 5, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        guard let msg = failureMessage(s, key) else { return }
        #expect(msg.lowercased().contains("every version"))
        #expect(msg.lowercased().contains("copyright"))
    }

    @Test func retryNeverAsksRealDebridAboutAKnownBlockedVersionAgain() async {
        // A 451 is a fact about the hash, not about the moment. "Try Another Version" re-runs the
        // same ranked list, so the retry must move straight past the refused one rather than spend
        // its first request re-confirming the refusal — and it must not be lured by a fake that
        // would now let it through.
        let req = ScriptedReq(["h1": [.failure(RDAddError.blocked), .success(tv("queued", id: "T1"))],
                               "h2": [.failure(FakeError.boom), .success(tv("queued", id: "T2"))]])
        let s = make(req: req)
        let key = DownloadKey.movie(tmdbID: 6)
        await s.request(contentKey: key, tmdbID: 6, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        await s.request(contentKey: key, tmdbID: 6, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        #expect(req.calls == ["h1", "h2", "h2"])
        #expect(s.status(forContentKey: key)?.torrentID == "T2")
    }

    @Test func refreshUpdatesProgress() async {
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", contentKey: DownloadKey.movie(tmdbID: 9), tmdbID: 9, phase: .downloading, fraction: 0.4)]])
        let s = make(poller: poller)
        await s.refresh()
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 9))?.fraction == 0.4)
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 9))?.phase == .downloading)
    }

    @Test func refreshReadyFiresOnReadyAndClearsBadge() async {
        var readyFor: Int?
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", contentKey: DownloadKey.movie(tmdbID: 5), tmdbID: 5, phase: .ready, fraction: 1)]])
        let s = make(poller: poller, onReady: { readyFor = $0.tmdbID })
        await s.refresh()
        #expect(readyFor == 5)
        #expect(s.activeTiles.isEmpty)                                          // badge cleared; title now in library
        // …but the title's own status stays READY rather than vanishing: cleared, the title page's
        // control fell back to a pressable "Request Download" until the library caught up.
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 5))?.phase == .ready)
    }

    /// A finished download stays in the store as READY — and must not keep the poll loop alive. Its
    /// stop condition was "every status failed", which a ready status never satisfies: Seret asked
    /// Real-Debrid for its torrent list every interval for the rest of the session.
    @Test func aFinishedDownloadStopsThePolling() async {
        let key = DownloadKey.movie(tmdbID: 21)
        let poller = CountingPoller(first: [DownloadStatus(torrentID: "T1", contentKey: key, tmdbID: 21,
                                                          phase: .ready, fraction: 1)])
        let s = DownloadStore(service: FakeReq(.success(tv("downloading", id: "T1"))),
                              records: FakeRecords(), poller: poller, deleter: FakeDeleter(),
                              pollInterval: .milliseconds(30))
        await s.request(contentKey: key, tmdbID: 21, title: "X", kind: .movie, candidates: [stream("h1")])
        try? await Task.sleep(for: .milliseconds(300))      // ten intervals

        #expect(s.status(forContentKey: key)?.phase == .ready)
        #expect(poller.polls <= 2, "still polling: \(poller.polls) polls")
    }

    @Test func refreshFailedKeepsStatusForRetry() async {
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", contentKey: DownloadKey.movie(tmdbID: 3), tmdbID: 3, phase: .failed("dead"), fraction: 0)]])
        let s = make(poller: poller)
        await s.refresh()
        if case .failed = s.status(forContentKey: DownloadKey.movie(tmdbID: 3))?.phase {} else { Issue.record("expected failed retained") }
    }

    @Test func loadActiveSeedsBadgesFromPersistedRecords() async {
        let records = FakeRecords(seeded: [
            DownloadRequestData(torrentID: "TID", contentKey: DownloadKey.movie(tmdbID: 88), tmdbID: 88,
                                infoHash: "h", kind: .movie,
                                title: "Restored", requestedAt: Date(timeIntervalSince1970: 0))])
        let s = make(records: records)
        await s.loadActive()
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 88)) != nil)   // badge survives restart
    }

    /// The defect this re-key exists to fix: both episodes share a tmdbID.
    @Test func twoEpisodesOfOneShowTrackSeparately() async {
        let req = FakeReq(.failure(.boom),
                          perHash: ["h1": .success(tv("downloading", id: "T1")),
                                    "h2": .success(tv("downloading", id: "T2"))])
        let s = make(req: req)
        await s.request(contentKey: "show:tmdb:1399:s1e1", tmdbID: 1399, title: "S1E1",
                        kind: .show, candidates: [stream("h1")])
        await s.request(contentKey: "show:tmdb:1399:s1e2", tmdbID: 1399, title: "S1E2",
                        kind: .show, candidates: [stream("h2")])
        #expect(s.status(forContentKey: "show:tmdb:1399:s1e1") != nil)
        #expect(s.status(forContentKey: "show:tmdb:1399:s1e2") != nil)
        #expect(s.activeTiles.count == 2)
    }

    /// The same collision on the poll path, which is how episodes arrive after a restart or when
    /// the download was started on another device.
    @Test func twoEpisodesOfOneShowStaySeparateAcrossAPoll() async {
        let s = make()
        await s.applyForTest([
            DownloadStatus(torrentID: "T1", contentKey: "show:tmdb:1399:s1e1", tmdbID: 1399,
                           phase: .downloading, fraction: 0.2, title: "S1E1"),
            DownloadStatus(torrentID: "T2", contentKey: "show:tmdb:1399:s1e2", tmdbID: 1399,
                           phase: .downloading, fraction: 0.8, title: "S1E2"),
        ])
        #expect(s.status(forContentKey: "show:tmdb:1399:s1e1")?.fraction == 0.2)
        #expect(s.status(forContentKey: "show:tmdb:1399:s1e2")?.fraction == 0.8)
        #expect(s.activeTiles.count == 2)
    }

    @Test func aFailingPollBacksOffExponentiallyAndRecovers() async {
        let poller = FakePoller([])
        let s = make(poller: poller)
        #expect(s.pollBackoff == .zero)

        poller.shouldThrow = true
        await s.refresh()
        #expect(s.pollBackoff == .seconds(5))
        await s.refresh()
        #expect(s.pollBackoff == .seconds(10))
        await s.refresh()
        #expect(s.pollBackoff == .seconds(20))

        poller.shouldThrow = false
        await s.refresh()
        #expect(s.pollBackoff == .zero)   // one good poll clears it
    }

    @Test func backoffIsCapped() async {
        let poller = FakePoller([])
        poller.shouldThrow = true
        let s = make(poller: poller)
        for _ in 0..<10 { await s.refresh() }
        #expect(s.pollBackoff == .seconds(60))
    }

    /// Two foreign downloads TMDB could not identify both have an empty content key.
    @Test func twoUnidentifiedDownloadsDoNotCollide() async {
        let s = make()
        await s.applyForTest([
            DownloadStatus(torrentID: "A", tmdbID: 0, phase: .downloading, fraction: 0.1),
            DownloadStatus(torrentID: "B", tmdbID: 0, phase: .downloading, fraction: 0.9),
        ])
        #expect(s.activeTiles.count == 2)
    }

    /// A download Seret did not start has no record, so its tile must come from the status itself.
    @Test func aForeignDownloadStillProducesATile() async {
        let s = make()
        await s.applyForTest([
            DownloadStatus(torrentID: "Z", contentKey: "movie:tmdb:42", tmdbID: 42,
                           phase: .downloading, fraction: 0.5, title: "Foreign",
                           posterPath: "/f.jpg")
        ])
        let tile = s.activeTiles.first
        #expect(tile?.title == "Foreign")
        #expect(tile?.posterPath == "/f.jpg")
    }
}
