import Testing
import Foundation
@testable import DebridCore

/// A refresh that finds ANY delta re-fetched `/torrents/info` for every torrent in the account,
/// however small the change. Adding one title to a large library meant one request per torrent it
/// already had, for content already sitting in the snapshot.
///
/// The whole risk of fetching less is losing something, so these tests are written around what must
/// SURVIVE, not around the request count alone — the count is only the last assertion in each.
extension MockTests {
    @Suite struct LibraryIncrementalRefreshTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "T" }
        }

        private func tempDir() -> URL {
            let dir = FileManager.default.temporaryDirectory.appending(path: "seret-inc-\(UUID().uuidString)")
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

        private static func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
             Data(json.utf8))
        }

        /// A torrent list row. `status` matters: it is what the delta check compares.
        private static func listJSON(_ rows: [(id: String, status: String)]) -> String {
            let body = rows.map { row in
                #"{"id":"\#(row.id)","filename":"\#(row.id).mkv","hash":"h","bytes":1,"host":"rd","progress":100,"status":"\#(row.status)","added":"2024-01-01T00:00:00Z","links":["https://rd/\#(row.id)"]}"#
            }
            return "[\(body.joined(separator: ","))]"
        }

        private static func infoJSON(_ id: String, release: String) -> String {
            #"{"id":"\#(id)","filename":"\#(release)","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/\#(release)","bytes":1,"selected":1}],"links":["https://rd/\#(id)"]}"#
        }

        /// Records which `/torrents/info/{id}` calls were actually made.
        private final class InfoCalls: @unchecked Sendable {
            private let lock = NSLock()
            private var ids: [String] = []
            func record(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return ids }
        }

        /// Serves a library of movies, one torrent each, recording every info call.
        private func handler(movies: [(id: String, title: String, tmdb: Int)],
                            status: String = "downloaded",
                            calls: InfoCalls) -> @Sendable (URLRequest) -> (HTTPURLResponse, Data) {
            let byID = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            let rows = movies.map { (id: $0.id, status: status) }
            return { req in
                let url = req.url!.absoluteString
                if let range = url.range(of: "/torrents/info/") {
                    let id = String(url[range.upperBound...])
                    calls.record(id)
                    guard let m = byID[id] else { return Self.resp(req, 404, "{}") }
                    return Self.resp(req, 200, Self.infoJSON(id, release: "\(m.title).2024.1080p.mkv"))
                }
                if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                if url.contains("/search/movie") {
                    let q = URLComponents(string: url)?.queryItems?
                        .first { $0.name == "query" }?.value ?? ""
                    guard let m = movies.first(where: { $0.title == q }) else {
                        return Self.resp(req, 200, #"{"results":[]}"#)
                    }
                    return Self.resp(req, 200, #"{"results":[{"id":\#(m.tmdb),"title":"\#(m.title)","release_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#)
                }
                return Self.resp(req, 200, "[]")
            }
        }

        // MARK: -

        @Test func addingOneTitleKeepsEveryOtherOneAndOnlyLooksUpTheNewTorrent() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            let existing = [("A", "Alpha", 111), ("B", "Beta", 222), ("C", "Gamma", 333)]
                .map { (id: $0.0, title: $0.1, tmdb: $0.2) }

            let firstPass = InfoCalls()
            MockURLProtocol.handler = handler(movies: existing, calls: firstPass)
            #expect(try await svc.refresh().count == 3)
            #expect(firstPass.all.count == 3)          // cold load looks up everything, as it must

            // One title added.
            let withNew = existing + [(id: "D", title: "Delta", tmdb: 444)]
            let secondPass = InfoCalls()
            MockURLProtocol.handler = handler(movies: withNew, calls: secondPass)
            let library = try await svc.refresh()

            // Nothing lost, and the new one is there — with its metadata.
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222, 333, 444])
            #expect(library.first { $0.tmdbID == 111 }?.title == "Alpha")
            #expect(library.first { $0.tmdbID == 444 }?.title == "Delta")
            // …and only the new torrent was looked up.
            #expect(secondPass.all == ["D"])
        }

        @Test func aDeletedTorrentTakesItsTitleWithItAndLooksUpNothing() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            let existing = [(id: "A", title: "Alpha", tmdb: 111), (id: "B", title: "Beta", tmdb: 222)]

            MockURLProtocol.handler = handler(movies: existing, calls: InfoCalls())
            _ = try await svc.refresh()

            let remaining = [(id: "A", title: "Alpha", tmdb: 111)]
            let secondPass = InfoCalls()
            MockURLProtocol.handler = handler(movies: remaining, calls: secondPass)
            let library = try await svc.refresh()

            #expect(library.compactMap(\.tmdbID) == [111])
            #expect(secondPass.all.isEmpty)            // nothing new to look up
        }

        /// The case incremental refresh is most likely to get wrong: a SHOW whose episodes come from
        /// several torrents. Adding one episode must not lose the others.
        @Test func addingAnEpisodeToAShowKeepsTheEpisodesAlreadyThere() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)

            func showHandler(_ episodes: [Int], calls: InfoCalls) -> @Sendable (URLRequest) -> (HTTPURLResponse, Data) {
                let rows = episodes.map { (id: "E\($0)", status: "downloaded") }
                return { req in
                    let url = req.url!.absoluteString
                    if let range = url.range(of: "/torrents/info/") {
                        let id = String(url[range.upperBound...])
                        calls.record(id)
                        let n = Int(id.dropFirst()) ?? 1
                        return Self.resp(req, 200, Self.infoJSON(id, release: "The.Show.S01E0\(n).1080p.mkv"))
                    }
                    if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                    if url.contains("/search/tv") {
                        return Self.resp(req, 200, #"{"results":[{"id":900,"name":"The Show","first_air_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#)
                    }
                    return Self.resp(req, 200, "[]")
                }
            }

            MockURLProtocol.handler = showHandler([1, 2], calls: InfoCalls())
            let first = try await svc.refresh()
            #expect(first.first?.seasons.first?.episodes.map(\.number).sorted() == [1, 2])

            let secondPass = InfoCalls()
            MockURLProtocol.handler = showHandler([1, 2, 3], calls: secondPass)
            let second = try await svc.refresh()

            #expect(second.count == 1)
            #expect(second.first?.tmdbID == 900)
            #expect(second.first?.seasons.first?.episodes.map(\.number).sorted() == [1, 2, 3])
        }

        /// Removing one VERSION of a movie leaves the movie with the other version, and the item's
        /// metadata intact.
        @Test func removingOneVersionOfAMovieKeepsTheMovie() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)

            func versionHandler(_ ids: [String], calls: InfoCalls) -> @Sendable (URLRequest) -> (HTTPURLResponse, Data) {
                let rows = ids.map { (id: $0, status: "downloaded") }
                return { req in
                    let url = req.url!.absoluteString
                    if let range = url.range(of: "/torrents/info/") {
                        let id = String(url[range.upperBound...])
                        calls.record(id)
                        let res = id == "HD" ? "1080p" : "2160p"
                        return Self.resp(req, 200, Self.infoJSON(id, release: "Alpha.2024.\(res).mkv"))
                    }
                    if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                    if url.contains("/search/movie") {
                        return Self.resp(req, 200, #"{"results":[{"id":111,"title":"Alpha","release_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#)
                    }
                    return Self.resp(req, 200, "[]")
                }
            }

            MockURLProtocol.handler = versionHandler(["HD", "UHD"], calls: InfoCalls())
            #expect(try await svc.refresh().first?.sources.count == 2)

            MockURLProtocol.handler = versionHandler(["HD"], calls: InfoCalls())
            let after = try await svc.refresh()
            #expect(after.count == 1)
            #expect(after.first?.tmdbID == 111)
            #expect(after.first?.sources.map(\.torrentID) == ["HD"])
        }

        /// A torrent that finishes downloading changes only its status, and must be looked up again
        /// — that transition is when it first has files to group.
        @Test func aStatusChangeReLooksUpJustThatTorrent() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            let movies = [(id: "A", title: "Alpha", tmdb: 111), (id: "B", title: "Beta", tmdb: 222)]

            MockURLProtocol.handler = handler(movies: movies, calls: InfoCalls())
            _ = try await svc.refresh()

            // B flips to a different status; A is untouched.
            let calls = InfoCalls()
            let rows = [(id: "A", status: "downloaded"), (id: "B", status: "downloading")]
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if let range = url.range(of: "/torrents/info/") {
                    let id = String(url[range.upperBound...])
                    calls.record(id)
                    return Self.resp(req, 200, Self.infoJSON(id, release: "\(id == "A" ? "Alpha" : "Beta").2024.1080p.mkv"))
                }
                if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                if url.contains("/search/movie") { return Self.resp(req, 200, #"{"results":[]}"#) }
                return Self.resp(req, 200, "[]")
            }
            let library = try await svc.refresh()

            #expect(calls.all == ["B"])
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222])   // both survive
        }

        /// The invariant the whole scheme rests on: a torrent we deliberately did NOT fetch must
        /// still be recorded as settled. If it is not, the next refresh sees it as changed, and the
        /// account re-fetches itself forever.
        @Test func aRefreshAfterAnIncrementalOneTakesTheCheapPath() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            let existing = [(id: "A", title: "Alpha", tmdb: 111), (id: "B", title: "Beta", tmdb: 222)]

            MockURLProtocol.handler = handler(movies: existing, calls: InfoCalls())
            _ = try await svc.refresh()

            let withNew = existing + [(id: "C", title: "Gamma", tmdb: 333)]
            MockURLProtocol.handler = handler(movies: withNew, calls: InfoCalls())
            _ = try await svc.refresh()

            // Nothing has changed since. No info call at all, and the library is intact.
            let third = InfoCalls()
            MockURLProtocol.handler = handler(movies: withNew, calls: third)
            let library = try await svc.refresh()

            #expect(third.all.isEmpty)
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222, 333])
        }

        /// A second VERSION of a title already owned: the new torrent groups on its own, and has to
        /// fold into the entry that was carried through rather than sitting beside it as a
        /// duplicate card.
        @Test func aSecondVersionOfAnOwnedTitleMergesIntoIt() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)

            func versions(_ ids: [String], calls: InfoCalls) -> @Sendable (URLRequest) -> (HTTPURLResponse, Data) {
                let rows = ids.map { (id: $0, status: "downloaded") }
                return { req in
                    let url = req.url!.absoluteString
                    if let range = url.range(of: "/torrents/info/") {
                        let id = String(url[range.upperBound...])
                        calls.record(id)
                        let res = id == "HD" ? "1080p" : "2160p"
                        return Self.resp(req, 200, Self.infoJSON(id, release: "Alpha.2024.\(res).mkv"))
                    }
                    if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                    if url.contains("/search/movie") {
                        return Self.resp(req, 200, #"{"results":[{"id":111,"title":"Alpha","release_date":"2024-01-01","poster_path":"/p.jpg","overview":"o"}]}"#)
                    }
                    return Self.resp(req, 200, "[]")
                }
            }

            MockURLProtocol.handler = versions(["HD"], calls: InfoCalls())
            #expect(try await svc.refresh().count == 1)

            let second = InfoCalls()
            MockURLProtocol.handler = versions(["HD", "UHD"], calls: second)
            let library = try await svc.refresh()

            #expect(library.count == 1)                                    // ONE card, not two
            #expect(library[0].tmdbID == 111)
            #expect(library[0].sources.map(\.torrentID).sorted() == ["HD", "UHD"])
            #expect(second.all == ["UHD"])                                 // only the new one
        }

        /// A transient info failure on the ONE torrent being re-fetched must not erase its title,
        /// and must not be recorded as settled — the next refresh has to try again.
        @Test func aFailedReFetchKeepsTheTitleAndRetriesNextTime() async throws {
            let dir = tempDir()
            let svc = service(directory: dir)
            let existing = [(id: "A", title: "Alpha", tmdb: 111), (id: "B", title: "Beta", tmdb: 222)]

            MockURLProtocol.handler = handler(movies: existing, calls: InfoCalls())
            _ = try await svc.refresh()

            // C is added, and its info call fails.
            let rows = [(id: "A", status: "downloaded"), (id: "B", status: "downloaded"),
                        (id: "C", status: "downloaded")]
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/torrents/info/C") { return Self.resp(req, 500, "{}") }
                if let range = url.range(of: "/torrents/info/") {
                    let id = String(url[range.upperBound...])
                    let title = id == "A" ? "Alpha" : "Beta"
                    return Self.resp(req, 200, Self.infoJSON(id, release: "\(title).2024.1080p.mkv"))
                }
                if url.contains("/torrents") { return Self.resp(req, 200, Self.listJSON(rows)) }
                return Self.resp(req, 200, #"{"results":[]}"#)
            }
            let afterFailure = try await svc.refresh()
            #expect(Set(afterFailure.compactMap(\.tmdbID)) == [111, 222])   // the two survive

            // C works now — and must be reconsidered, not treated as a known state.
            let retry = InfoCalls()
            MockURLProtocol.handler = handler(
                movies: existing + [(id: "C", title: "Gamma", tmdb: 333)], calls: retry)
            let library = try await svc.refresh()

            #expect(retry.all == ["C"])
            #expect(Set(library.compactMap(\.tmdbID)) == [111, 222, 333])
        }
    }
}
