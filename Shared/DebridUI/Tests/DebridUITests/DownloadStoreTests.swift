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
                      onReady: @escaping (DownloadStatus) -> Void = { _ in }) -> DownloadStore {
        DownloadStore(service: req, records: records, poller: poller, deleter: deleter,
                      onReady: { onReady($0) })
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
        #expect(s.status(forContentKey: DownloadKey.movie(tmdbID: 5)) == nil)   // badge cleared; title now in library
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
