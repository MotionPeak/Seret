import Foundation
import Testing
@testable import DebridCore

struct TorBoxMappingTests {
    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(json.utf8))
    }

    private static func torrent(_ json: String) throws -> TorBoxTorrent {
        try decode(TorBoxEnvelope<TorBoxTorrent>.self, #"{"success":true,"error":null,"detail":"ok","data":\#(json)}"#).data!
    }

    private static func file(_ id: Int, _ name: String, size: Int = 1000, mime: String = "video/x-matroska",
                             zipped: Bool = false) -> String {
        #"{"id":\#(id),"name":"\#(name)","short_name":"\#(name)","size":\#(size),"mimetype":"\#(mime)","zipped":\#(zipped)}"#
    }

    @Test func mapsReadyMovieTorrent() throws {
        let t = try Self.torrent("""
        {"id":7,"hash":"abc","name":"Dune.2021","size":5000,"created_at":"2024-03-01T12:00:00Z",
         "download_state":"cached","download_finished":true,"download_present":true,"progress":1,
         "download_speed":0,"seeds":0,
         "files":[\(Self.file(0, "Dune.2021/Dune.2021.mkv", size: 4900)),
                  \(Self.file(1, "Dune.2021/Dune.2021.nfo", size: 100, mime: "text/plain"))]}
        """)
        let info = TorBoxMapping.info(t)
        #expect(info.id == "tb:7")
        #expect(info.status == "downloaded")
        #expect(info.filename == "Dune.2021")
        #expect(info.bytes == 5000)
        #expect(info.progress == 100)
        #expect(info.added == "2024-03-01T12:00:00Z")
        #expect(info.files.map(\.selected) == [1, 0])
        #expect(info.files[0].path == "Dune.2021/Dune.2021.mkv")
        #expect(info.files[0].bytes == 4900)
        #expect(info.links == ["torbox://tb:7/0"])
        #expect(info.primaryVideoFile()?.link == "torbox://tb:7/0")

        let summary = TorBoxMapping.torrent(t)
        #expect(summary.id == "tb:7")
        #expect(summary.host == "torbox")
        #expect(summary.status == "downloaded")
        #expect(summary.links == ["torbox://tb:7/0"])
        #expect(summary.hash == "abc")
    }

    @Test func seasonPackEpisodeLookup() throws {
        let t = try Self.torrent("""
        {"id":9,"hash":"h","name":"Show.S01","size":3000,"download_present":true,"progress":1,
         "files":[\(Self.file(4, "Show.S01/Show.S01E01.mkv")),
                  \(Self.file(5, "Show.S01/Show.S01E02.mkv")),
                  \(Self.file(6, "Show.S01/Show.S01E03.mkv"))]}
        """)
        let info = TorBoxMapping.info(t)
        #expect(info.links == ["torbox://tb:9/4", "torbox://tb:9/5", "torbox://tb:9/6"])
        #expect(info.videoFile(forSeason: 1, episode: 2)?.link == "torbox://tb:9/5")
    }

    @Test func zippedTorrentHasNoVideoLinks() throws {
        let t = try Self.torrent("""
        {"id":3,"hash":"h","name":"Zipped","size":900,"download_present":true,"progress":1,
         "files":[\(Self.file(0, "Zipped/Movie.mkv", zipped: true)),
                  \(Self.file(1, "Zipped.zip", mime: "application/zip"))]}
        """)
        let info = TorBoxMapping.info(t)
        #expect(info.status == "downloaded")
        #expect(info.files.allSatisfy { $0.selected == 0 })
        #expect(info.links.isEmpty)
        #expect(info.primaryVideoFile() == nil)
    }

    @Test func downloadingTorrentMapsToDownloading() throws {
        let t = try Self.torrent("""
        {"id":5,"hash":"h","name":"Slow","size":900,"download_state":"stalled (no seeds)",
         "download_finished":false,"download_present":false,"progress":0.25,"download_speed":10,"seeds":0,
         "files":[\(Self.file(0, "Slow/Movie.mkv"))]}
        """)
        let info = TorBoxMapping.info(t)
        #expect(info.status == "downloading")
        #expect(info.progress == 25)
        #expect(info.speed == 10)
        #expect(info.seeders == 0)
        #expect(info.files[0].selected == 1)
        #expect(info.links.isEmpty)
        #expect(info.primaryVideoFile() == nil)
        #expect(TorBoxMapping.torrent(t).links.isEmpty)
    }

    @Test func statusVocabulary() throws {
        func status(_ state: String?, present: Bool? = nil, finished: Bool? = nil) throws -> String {
            let stateJSON = state.map { #""\#($0)""# } ?? "null"
            let t = try Self.torrent(#"""
            {"id":1,"hash":"h","name":"n","size":1,"download_state":\#(stateJSON),
             "download_present":\#(present.map(String.init(describing:)) ?? "null"),
             "download_finished":\#(finished.map(String.init(describing:)) ?? "null")}
            """#)
            return TorBoxMapping.status(t)
        }
        #expect(try status("downloading") == "downloading")
        #expect(try status("uploading") == "downloading")
        #expect(try status("cached") == "downloaded")
        #expect(try status("completed") == "downloaded")
        #expect(try status("downloading", present: true) == "downloaded")
        #expect(try status("downloading", finished: true) == "downloaded")
        #expect(try status("error") == "error")
        #expect(try status("failed (Error: disk)") == "error")
        #expect(try status("paused") == "queued")
        #expect(try status("queued") == "queued")
        #expect(try status("checkingResumeData") == "queued")
        #expect(try status(nil) == "downloading")
    }

    @Test func metaDLMapsToMagnetConversion() throws {
        let t = try Self.torrent(#"{"id":2,"hash":"h","name":"n","size":0,"download_state":"metaDL","progress":0}"#)
        #expect(TorBoxMapping.status(t) == "magnet_conversion")
        #expect(TorBoxMapping.info(t).files.isEmpty)
        #expect(TorBoxMapping.info(t).links.isEmpty)
    }

    @Test func linkRoundTrip() {
        #expect(TorBoxMapping.torrentID(42) == "tb:42")
        #expect(TorBoxMapping.numericID("tb:42") == 42)
        #expect(TorBoxMapping.numericID("ABCDEF") == nil)
        #expect(TorBoxMapping.numericID("tb:x") == nil)
        let link = TorBoxMapping.link(torrentID: 42, fileID: 3)
        #expect(link == "torbox://tb:42/3")
        let parsed = TorBoxMapping.parseLink(link)
        #expect(parsed?.torrentID == 42)
        #expect(parsed?.fileID == 3)
        #expect(TorBoxMapping.parseLink("https://real-debrid.com/d/XYZ") == nil)
        #expect(TorBoxMapping.parseLink("torbox://tb:42") == nil)
        #expect(DebridProvider.of(link: link) == .torBox)
        #expect(DebridProvider.of(torrentID: TorBoxMapping.torrentID(42)) == .torBox)
    }

    @Test func envelopeErrorDecodes() throws {
        let env = try Self.decode(TorBoxEnvelope<TorBoxTorrent>.self, """
        {"success":false,"error":"PLAN_RESTRICTED_FEATURE","detail":"API feature not available on your plan.","data":null}
        """)
        #expect(env.success == false)
        #expect(env.data == nil)
        let err = TorBoxError.api(code: env.error ?? "", detail: env.detail ?? "", status: 403)
        #expect(err.isPlanRestricted)
        #expect(!err.isAuthRejection)
        #expect(err.userMessage == "TorBox's API needs a paid plan.")

        let bad = TorBoxError.api(code: "BAD_TOKEN", detail: "Invalid token.", status: 401)
        #expect(bad.isAuthRejection)
        #expect(!bad.isPlanRestricted)
        #expect(bad.userMessage == "Invalid token.")
        #expect(TorBoxError.api(code: "NO_AUTH", detail: "", status: 401).isAuthRejection)
        #expect(TorBoxError.api(code: "AUTH_ERROR", detail: "", status: 401).isAuthRejection)
        #expect(TorBoxError.rateLimited(retryAfter: 300).userMessage == "TorBox is busy — try again in a few minutes.")
        #expect(!TorBoxError.rateLimited(retryAfter: nil).isAuthRejection)
        #expect(!TorBoxError.notSignedIn.isPlanRestricted)
    }

    @Test func userPlanNames() throws {
        let free = try Self.decode(TorBoxUser.self, """
        {"id":1,"plan":0,"email":"a@b.c","premium_expires_at":"2026-09-25T12:45:33Z","is_subscribed":false}
        """)
        #expect(free.planName == "Free")
        #expect(!free.isPaid)
        #expect(free.email == "a@b.c")
        #expect(free.premiumExpiresAt == "2026-09-25T12:45:33Z")
        func name(_ plan: Int) throws -> String {
            try Self.decode(TorBoxUser.self, #"{"plan":\#(plan)}"#).planName
        }
        #expect(try name(1) == "Essential")
        #expect(try name(2) == "Pro")
        #expect(try name(3) == "Standard")
        #expect(try name(9) == "Plan 9")
        #expect(try Self.decode(TorBoxUser.self, #"{"plan":2}"#).isPaid)
    }
}
