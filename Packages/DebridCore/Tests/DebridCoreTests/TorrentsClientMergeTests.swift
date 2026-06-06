import Testing
import Foundation
@testable import DebridCore

@Suite struct TorrentsClientMergeTests {
    @Test func attachesAddedById() {
        let infos = [
            TorrentInfo(id: "a", filename: "fa", hash: "h", bytes: 1, progress: 100, status: "downloaded", files: [], links: [], added: nil),
            TorrentInfo(id: "b", filename: "fb", hash: "h", bytes: 1, progress: 100, status: "downloaded", files: [], links: [], added: nil),
        ]
        let torrents = [
            Torrent(id: "a", filename: "fa", hash: "h", bytes: 1, host: "x", progress: 100, status: "downloaded", added: "2026-06-01T00:00:00.000Z", links: []),
        ]
        let merged = TorrentsClient.attachAddedDates(infos: infos, torrents: torrents)
        #expect(merged.first { $0.id == "a" }?.added == "2026-06-01T00:00:00.000Z")
        #expect(merged.first { $0.id == "b" }?.added == nil)
    }
}
