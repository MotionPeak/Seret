import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct LibraryServiceRemoveTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "seret-rm-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        private func service(directory: URL) -> LibraryService {
            let http = HTTPClient(session: .mock)
            return LibraryService(
                torrents: TorrentsClient(http: http, tokens: StubTokens()),
                builder: LibraryBuilder(),
                enricher: MetadataEnricher(tmdb: TMDBClient(apiKey: "K", http: http)),
                store: LibrarySnapshotStore(directory: directory))
        }

        private func src(_ torrentID: String) -> MediaSource {
            MediaSource(torrentID: torrentID, fileID: nil, restrictedLink: "https://rd/\(torrentID)",
                        parsed: ParsedRelease(title: "x"))
        }
        private func movie(_ id: String, torrents ids: [String]) -> MediaItem {
            MediaItem(id: id, kind: .movie, title: "M \(id)", year: 2024,
                      sources: ids.map(src), seasons: [])
        }

        @Test func deletesAllTorrentsForAMovieAndDropsFromSnapshot() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("keep", torrents: ["K1"]),
                                        movie("gone", torrents: ["A", "B"])]))
            let box = RecordedDeletes()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                return Self.resp(req, 204)
            }
            try await svc.remove(movie("gone", torrents: ["A", "B"]))
            #expect(Set(box.values) == ["A", "B"])
            #expect(svc.loadCached()?.map(\.id) == ["keep"])
        }

        @Test func treats404AsSuccess() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A"])]))
            MockURLProtocol.handler = { req in Self.resp(req, 404) }
            try await svc.remove(movie("gone", torrents: ["A"]))   // must NOT throw
            #expect(svc.loadCached()?.isEmpty == true)
        }

        @Test func nonNotFoundFailureThrowsAndPreservesSnapshot() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A"])]))
            MockURLProtocol.handler = { req in Self.resp(req, 500) }
            await #expect(throws: (any Error).self) {
                try await svc.remove(movie("gone", torrents: ["A"]))
            }
            #expect(svc.loadCached()?.map(\.id) == ["gone"])   // snapshot untouched
        }

        @Test func midLoop404ContinuesToNextTorrentAndDropsFromSnapshot() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A", "B"])]))
            let box = RecordedDeletes()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                let status = req.url!.lastPathComponent == "A" ? 204 : 404
                return Self.resp(req, status)
            }
            try await svc.remove(movie("gone", torrents: ["A", "B"]))   // must NOT throw
            #expect(Set(box.values) == ["A", "B"])
            #expect(svc.loadCached()?.isEmpty == true)
        }

        @Test func multiTorrentNonNotFoundFailureThrowsAndPreservesSnapshot() async throws {
            // One torrent succeeds (204), the other fails (500). Whichever order the (Set-derived)
            // ids run, remove() must throw and leave the snapshot untouched — even if one torrent
            // was already deleted on RD. The next refresh() reconciles the divergence.
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("gone", torrents: ["A", "B"])]))
            let box = RecordedDeletes()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                let status = req.url!.lastPathComponent == "A" ? 204 : 500
                return Self.resp(req, status)
            }
            await #expect(throws: (any Error).self) {
                try await svc.remove(movie("gone", torrents: ["A", "B"]))
            }
            #expect(!box.values.isEmpty)                       // at least one delete was attempted
            #expect(svc.loadCached()?.map(\.id) == ["gone"])   // snapshot untouched on failure
        }

        private func show(_ id: String, seasons: [Season]) -> MediaItem {
            MediaItem(id: id, kind: .show, title: "S \(id)", year: 2024,
                      sources: [], seasons: seasons)
        }

        @Test func deletesUniqueEpisodeTorrentIdsForShowAndDropsFromSnapshot() async throws {
            // Two episodes share torrent "T1"; a third uses "T2" — dedup must yield exactly {T1, T2}.
            let episodes: [Episode] = [
                Episode(season: 1, number: 1, source: src("T1")),
                Episode(season: 1, number: 2, source: src("T1")),
                Episode(season: 1, number: 3, source: src("T2")),
            ]
            let item = show("gone", seasons: [Season(number: 1, episodes: episodes)])
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(LibrarySnapshot(items: [item]))
            let box = RecordedDeletes()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                return Self.resp(req, 204)
            }
            try await svc.remove(item)
            #expect(Set(box.values) == ["T1", "T2"])
            #expect(svc.loadCached()?.isEmpty == true)
        }

        @Test func removeVersionDropsOneSourceAndDeletesOnlyThatTorrent() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("dune", torrents: ["A", "B", "C"])]))
            let box = RecordedDeletes()
            MockURLProtocol.handler = { req in
                if req.httpMethod == "DELETE" { box.append(req.url!.lastPathComponent) }
                return Self.resp(req, 204)
            }
            try await svc.removeVersion(movie("dune", torrents: ["A", "B", "C"]), source: src("B"))
            #expect(box.values == ["B"])
            #expect(svc.loadCached()?.first?.sources.map(\.torrentID) == ["A", "C"])
        }

        @Test func removeVersionLastSourceRemovesWholeItem() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            try LibrarySnapshotStore(directory: dir).save(
                LibrarySnapshot(items: [movie("dune", torrents: ["A"]),
                                        movie("keep", torrents: ["K"])]))
            MockURLProtocol.handler = { req in Self.resp(req, 204) }
            try await svc.removeVersion(movie("dune", torrents: ["A"]), source: src("A"))
            #expect(svc.loadCached()?.map(\.id) == ["keep"])
        }

        private static func resp(_ req: URLRequest, _ status: Int) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
}

/// Thread-safe recorder for DELETE paths captured inside the @Sendable mock handler.
/// Named distinctly from TorrentsAddTests.DeletedBox (which only tracks a boolean).
private final class RecordedDeletes: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    func append(_ s: String) { lock.lock(); _values.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return _values }
}
