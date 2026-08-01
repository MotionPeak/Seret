import Testing
import Foundation
@testable import DebridCore

/// RD sends `speed` (bytes/sec) and `seeders` only while a torrent is downloading — both must
/// survive decoding when present and degrade to nil when absent.
@Suite struct TorrentSpeedDecodingTests {
    @Test func infoDecodesSpeedAndSeeders() throws {
        let json = Data("""
        {"id":"T1","filename":"f.mkv","hash":"abc","bytes":1000,"progress":25.0,
         "status":"downloading","files":[],"links":[],"speed":5242880,"seeders":12}
        """.utf8)
        let info = try JSONDecoder().decode(TorrentInfo.self, from: json)
        #expect(info.speed == 5_242_880)
        #expect(info.seeders == 12)
    }

    @Test func infoWithoutSpeedDecodesToNil() throws {
        let json = Data("""
        {"id":"T1","filename":"f.mkv","hash":"abc","bytes":1000,"progress":100.0,
         "status":"downloaded","files":[],"links":[]}
        """.utf8)
        let info = try JSONDecoder().decode(TorrentInfo.self, from: json)
        #expect(info.speed == nil)
        #expect(info.seeders == nil)
    }

    @Test func listItemDecodesSpeedAndSeeders() throws {
        let json = Data("""
        {"id":"T1","filename":"f.mkv","hash":"abc","bytes":1000,"host":"real-debrid.com",
         "progress":25.0,"status":"downloading","added":"2026-08-01T10:00:00.000Z","links":[],
         "speed":1048576,"seeders":3}
        """.utf8)
        let t = try JSONDecoder().decode(Torrent.self, from: json)
        #expect(t.speed == 1_048_576)
        #expect(t.seeders == 3)
    }

    /// Guards the memberwise inits staying source-compatible: this call omits both new fields.
    @Test func memberwiseInitDefaultsSpeedAndSeedersToNil() {
        let info = TorrentInfo(id: "T", filename: "f", hash: "h", bytes: 1, progress: 0,
                               status: "queued", files: [], links: [])
        #expect(info.speed == nil)
        #expect(info.seeders == nil)
    }

    /// `allTorrentInfos()` rebuilds every TorrentInfo through `attachAddedDates` to carry `added`
    /// over from the list. If that rebuild drops the new fields, every ETA in the app is nil.
    @Test func attachingAddedDatesPreservesSpeedAndSeeders() {
        let info = TorrentInfo(id: "T1", filename: "f", hash: "h", bytes: 1000, progress: 25,
                               status: "downloading", files: [], links: [],
                               speed: 5_242_880, seeders: 12)
        let listItem = Torrent(id: "T1", filename: "f", hash: "h", bytes: 1000,
                               host: "real-debrid.com", progress: 25, status: "downloading",
                               added: "2026-08-01T10:00:00.000Z", links: [])
        let merged = TorrentsClient.attachAddedDates(infos: [info], torrents: [listItem])
        #expect(merged[0].added == "2026-08-01T10:00:00.000Z")
        #expect(merged[0].speed == 5_242_880)
        #expect(merged[0].seeders == 12)
    }
}
