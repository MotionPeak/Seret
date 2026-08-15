import Testing
import Foundation
import DebridCore
@testable import DebridUI

private enum FakeError: Error { case boom }

private func tv(_ status: String, id: String = "TID") -> TorrentInfo {
    TorrentInfo(id: id, filename: "M", hash: "h", bytes: 1, progress: 0, status: status,
                files: [TorrentFile(id: 1, path: "/M/m.mkv", bytes: 1, selected: 1)],
                links: ["https://rd/d/X"])
}

private final class FakeReq: DownloadRequesting, @unchecked Sendable {
    private(set) var startedHashes: [String] = []
    var result: Result<TorrentInfo, FakeError> = .success(tv("queued"))
    func startDownload(infoHash: String) async throws -> TorrentInfo {
        startedHashes.append(infoHash)
        return try result.get()
    }
}

private final class FakeRecords: DownloadRecording, @unchecked Sendable {
    private(set) var upserts: [DownloadRequestData] = []
    func upsert(_ data: DownloadRequestData) async throws { upserts.append(data) }
    func all() async throws -> [DownloadRequestData] { [] }
    func delete(torrentID: String) async throws {}
}

private final class FakeDeleter: DownloadDeleting, @unchecked Sendable {
    func deleteTorrent(id: String) async throws {}
}

private final class FakePoller: DownloadPolling, @unchecked Sendable {
    func poll() async throws -> [DownloadStatus] { [] }
}

@MainActor
@Suite struct MagnetAddModelTests {
    static let hex = "0123456789abcdef0123456789abcdef01234567"

    private func make(req: FakeReq = FakeReq())
        -> (MagnetAddModel, DownloadStore, FakeReq, FakeRecords) {
        let records = FakeRecords()
        let downloads = DownloadStore(service: req, records: records,
                                      poller: FakePoller(), deleter: FakeDeleter(),
                                      pollInterval: .milliseconds(10))
        let target = MagnetAddModel.Target(
            contentKey: DownloadKey.episode(showTmdbID: 15969, season: 1, number: 1),
            tmdbID: 15969, title: "HaPijamot", kind: .show, posterPath: "/p.jpg")
        return (MagnetAddModel(target: target, downloads: downloads), downloads, req, records)
    }

    @Test func startsIdle() {
        let (model, _, _, _) = make()
        #expect(model.state == .idle)
        #expect(model.canSubmit == false)
    }

    @Test func reportsInvalidPaste() {
        let (model, _, _, _) = make()
        model.update(text: "not a magnet")
        #expect(model.state == .invalid)
        #expect(model.canSubmit == false)
    }

    @Test func emptyTextReturnsToIdleNotInvalid() {
        let (model, _, _, _) = make()
        model.update(text: "junk")
        model.update(text: "   ")
        #expect(model.state == .idle)   // clearing the field is not an error
    }

    @Test func readyShowsTheReleaseName() {
        let (model, _, _, _) = make()
        model.update(text: "magnet:?xt=urn:btih:\(Self.hex)&dn=HaPijamot.S01E01")
        #expect(model.state == .ready(displayName: "HaPijamot.S01E01"))
        #expect(model.canSubmit == true)
    }

    @Test func submitStartsDownloadUnderTheTargetKey() async {
        let (model, downloads, req, records) = make()
        model.update(text: "magnet:?xt=urn:btih:\(Self.hex)&dn=HaPijamot.S01E01")
        await model.submit()

        #expect(model.state == .submitted)
        #expect(req.startedHashes == [Self.hex])
        let key = DownloadKey.episode(showTmdbID: 15969, season: 1, number: 1)
        #expect(downloads.status(forContentKey: key) != nil)
        #expect(records.upserts.first?.contentKey == key)
        #expect(records.upserts.first?.infoHash == Self.hex)
        #expect(records.upserts.first?.title == "HaPijamot")
    }

    @Test func submitWithoutValidLinkDoesNothing() async {
        let (model, _, req, _) = make()
        model.update(text: "junk")
        await model.submit()
        #expect(req.startedHashes.isEmpty)
    }

    @Test func surfacesAFailedStart() async {
        let req = FakeReq()
        req.result = .failure(.boom)
        let (model, _, _, _) = make(req: req)
        model.update(text: "magnet:?xt=urn:btih:\(Self.hex)")
        await model.submit()
        if case .failed = model.state {} else {
            Issue.record("expected .failed, got \(model.state)")
        }
    }
}
