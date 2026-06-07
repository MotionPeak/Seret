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
    init(_ fallback: Result<TorrentInfo, FakeError>, perHash: [String: Result<TorrentInfo, FakeError>] = [:]) {
        self.fallback = fallback; self.perHash = perHash
    }
    func startDownload(infoHash: String) async throws -> TorrentInfo { try (perHash[infoHash] ?? fallback).get() }
}

private final class FakeRecords: DownloadRecording, @unchecked Sendable {
    private(set) var upserts: [DownloadRequestData] = []
    private(set) var deleted: [String] = []
    var seeded: [DownloadRequestData]
    init(seeded: [DownloadRequestData] = []) { self.seeded = seeded }
    func upsert(_ data: DownloadRequestData) async throws { upserts.append(data) }
    func all() async throws -> [DownloadRequestData] { seeded }
    func delete(torrentID: String) async throws { deleted.append(torrentID) }
}

private final class FakeDeleter: DownloadDeleting, @unchecked Sendable {
    private(set) var deleted: [String] = []
    func deleteTorrent(id: String) async throws { deleted.append(id) }
}

private final class FakePoller: DownloadPolling, @unchecked Sendable {
    var passes: [[DownloadStatus]]
    init(_ passes: [[DownloadStatus]]) { self.passes = passes }
    func poll() async throws -> [DownloadStatus] { passes.isEmpty ? [] : passes.removeFirst() }
}

@MainActor
@Suite struct DownloadStoreTests {
    private func make(req: FakeReq = FakeReq(.success(tv("queued"))),
                      records: FakeRecords = FakeRecords(),
                      poller: FakePoller = FakePoller([]),
                      deleter: FakeDeleter = FakeDeleter(),
                      onReady: @escaping (Int) -> Void = { _ in }) -> DownloadStore {
        DownloadStore(service: req, records: records, poller: poller, deleter: deleter,
                      onReady: { onReady($0) })
    }

    @Test func cancelDeletesTorrentClearsRecordAndBadge() async {
        let records = FakeRecords()
        let deleter = FakeDeleter()
        let s = make(req: FakeReq(.success(tv("downloading", id: "TID"))), records: records, deleter: deleter)
        await s.request(tmdbID: 5, title: "X", kind: .movie, candidates: [stream("h")])
        #expect(s.status(forTMDB: 5) != nil)
        await s.cancel(tmdbID: 5)
        #expect(s.status(forTMDB: 5) == nil)          // badge gone
        #expect(deleter.deleted == ["TID"])           // RD torrent removed
        #expect(records.deleted == ["TID"])           // persisted record removed
    }

    @Test func requestStartsDownloadAndRecordsIt() async {
        let records = FakeRecords()
        let s = make(req: FakeReq(.success(tv("queued", id: "TID"))), records: records)
        await s.request(tmdbID: 42, title: "Obsession", kind: .movie, candidates: [stream("h1")])
        #expect(s.status(forTMDB: 42)?.phase == .queued)
        #expect(records.upserts.count == 1)
        #expect(records.upserts.first?.torrentID == "TID")
        #expect(records.upserts.first?.infoHash == "h1")
        #expect(records.upserts.first?.tmdbID == 42)
    }

    @Test func requestFallsBackThroughCandidates() async {
        // First candidate is a dead magnet; second starts.
        let req = FakeReq(.failure(.boom), perHash: ["h2": .success(tv("downloading", id: "T2"))])
        let records = FakeRecords()
        let s = make(req: req, records: records)
        await s.request(tmdbID: 7, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        #expect(s.status(forTMDB: 7)?.phase == .downloading)
        #expect(records.upserts.first?.infoHash == "h2")
    }

    @Test func requestWithNoCandidatesFails() async {
        let s = make()
        await s.request(tmdbID: 1, title: "X", kind: .movie, candidates: [])
        if case .failed = s.status(forTMDB: 1)?.phase {} else { Issue.record("expected failed") }
    }

    @Test func requestAllCandidatesFailMarksFailed() async {
        let s = make(req: FakeReq(.failure(.boom)))
        await s.request(tmdbID: 2, title: "X", kind: .movie, candidates: [stream("h1"), stream("h2")])
        if case .failed = s.status(forTMDB: 2)?.phase {} else { Issue.record("expected failed") }
    }

    @Test func refreshUpdatesProgress() async {
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", tmdbID: 9, phase: .downloading, fraction: 0.4)]])
        let s = make(poller: poller)
        await s.refresh()
        #expect(s.status(forTMDB: 9)?.fraction == 0.4)
        #expect(s.status(forTMDB: 9)?.phase == .downloading)
    }

    @Test func refreshReadyFiresOnReadyAndClearsBadge() async {
        var readyFor: Int?
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", tmdbID: 5, phase: .ready, fraction: 1)]])
        let s = make(poller: poller, onReady: { readyFor = $0 })
        await s.refresh()
        #expect(readyFor == 5)
        #expect(s.status(forTMDB: 5) == nil)   // badge cleared; title now in library
    }

    @Test func refreshFailedKeepsStatusForRetry() async {
        let poller = FakePoller([[DownloadStatus(torrentID: "TID", tmdbID: 3, phase: .failed("dead"), fraction: 0)]])
        let s = make(poller: poller)
        await s.refresh()
        if case .failed = s.status(forTMDB: 3)?.phase {} else { Issue.record("expected failed retained") }
    }

    @Test func loadActiveSeedsBadgesFromPersistedRecords() async {
        let records = FakeRecords(seeded: [
            DownloadRequestData(torrentID: "TID", tmdbID: 88, infoHash: "h", kind: .movie,
                                title: "Restored", requestedAt: Date(timeIntervalSince1970: 0))])
        let s = make(records: records)
        await s.loadActive()
        #expect(s.status(forTMDB: 88) != nil)   // badge survives restart
    }
}
