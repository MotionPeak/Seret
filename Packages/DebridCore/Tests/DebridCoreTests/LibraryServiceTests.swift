import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct LibraryServiceTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "seret-svc-\(UUID().uuidString)")
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

        // --- static response builders: the handler captures NOTHING (no self, no mutable var),
        //     so it stays @Sendable-safe under Swift 6. Two-pass tests reassign the handler
        //     between (sequential) refresh awaits rather than mutating captured state. ---
        private static func torrentListJSON(_ ids: [String]) -> String {
            let rows = ids.map { #"{"id":"\#($0)","filename":"\#($0).2024.1080p.mkv","hash":"h","bytes":1,"host":"rd","progress":100,"status":"downloaded","added":"2024-01-01T00:00:00Z","links":["https://rd/\#($0)"]}"# }
            return "[\(rows.joined(separator: ","))]"
        }
        private static func infoJSON(_ id: String, release: String) -> String {
            #"{"id":"\#(id)","filename":"\#(release)","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/\#(release)","bytes":1,"selected":1}],"links":["https://rd/\#(id)"]}"#
        }
        /// A torrent whose only file is non-video → `LibraryBuilder` produces NO item for it.
        private static func nonVideoInfoJSON(_ id: String) -> String {
            #"{"id":"\#(id)","filename":"\#(id).sample","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/readme.txt","bytes":1,"selected":1}],"links":["https://rd/\#(id)"]}"#
        }
        private static func tmdbJSON(id: Int, title: String) -> String {
            #"{"results":[{"id":\#(id),"title":"\#(title)","release_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        @Test func coldRefreshBuildsEnrichesAndPersists() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            let svc = service(directory: tempDir())
            #expect(svc.loadCached() == nil)                  // nothing yet

            let library = try await svc.refresh()
            #expect(library.count == 1)
            #expect(library[0].tmdbID == 111)
            #expect(library[0].title == "Alpha")
            #expect(svc.loadCached()?.first?.tmdbID == 111)   // persisted for next launch
        }

        @Test func unchangedRefreshReusesCacheWithoutTMDB() async throws {
            let svc = service(directory: tempDir())
            // 1st pass: enrich A from TMDB.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // 2nd pass: same torrents, but TMDB now 500s. If A were re-enriched the 500 would strip
            // its metadata; carrying the cache over means it stays enriched (TMDB not called).
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 500, "{}") }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()
            #expect(library.count == 1)
            #expect(library[0].tmdbID == 111)
        }

        @Test func deltaEnrichesOnlyNewItems() async throws {
            let svc = service(directory: tempDir())
            // 1st pass: [A] → A enriched to 111.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // 2nd pass: [A,B]. Alpha would now return 999 (proves A is NOT re-queried); Beta → 222.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents/info/B") { return Self.resp(req, 200, Self.infoJSON("B", release: "Beta.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A", "B"])) }
                if url.contains("/search/movie") {
                    if req.url!.absoluteString.contains("query=Beta") { return Self.resp(req, 200, Self.tmdbJSON(id: 222, title: "Beta")) }
                    return Self.resp(req, 200, Self.tmdbJSON(id: 999, title: "Alpha"))
                }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222])   // A kept 111 (carried), B got 222 (new)
        }

        @Test func nonVideoTorrentDoesNotForcePerpetualRefresh() async throws {
            let svc = service(directory: tempDir())
            // 1st pass: library has A (a movie) + Z (a non-video torrent → no item). A → 111.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents/info/Z") { return Self.resp(req, 200, Self.nonVideoInfoJSON("Z")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A", "Z"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // 2nd pass: IDENTICAL torrents. The torrent LIST still works, but every `/torrents/info`
            // now 500s. The cache holds only A's id while RD reports {A,Z}; deriving the delta from
            // items sees Z as "new" forever → it re-runs the expensive `allTorrentInfos()` fan-out,
            // the 500s wipe everything, and the library collapses to empty. Tracking the seen
            // torrent-id set means no delta → the info fan-out is skipped entirely and the cache is
            // returned untouched.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info") { return Self.resp(req, 500, "{}") }
                if url.contains("/torrents")      { return Self.resp(req, 200, Self.torrentListJSON(["A", "Z"])) }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()
            #expect(library.count == 1)            // cheap path: info fan-out skipped, cache reused
            #expect(library[0].tmdbID == 111)
        }

        @Test func refreshFailureLeavesCacheReadable() async throws {
            let svc = service(directory: tempDir())
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/A") { return Self.resp(req, 200, Self.infoJSON("A", release: "Alpha.2024.1080p.mkv")) }
                if url.contains("/torrents")        { return Self.resp(req, 200, Self.torrentListJSON(["A"])) }
                if url.contains("/search/movie")    { return Self.resp(req, 200, Self.tmdbJSON(id: 111, title: "Alpha")) }
                return Self.resp(req, 200, "[]")
            }
            _ = try await svc.refresh()
            // now every RD call 500s → refresh throws, but the cache still loads
            MockURLProtocol.handler = { req in Self.resp(req, 500, "{}") }
            await #expect(throws: (any Error).self) { try await svc.refresh() }
            #expect(svc.loadCached()?.first?.tmdbID == 111)
        }
    }
}
