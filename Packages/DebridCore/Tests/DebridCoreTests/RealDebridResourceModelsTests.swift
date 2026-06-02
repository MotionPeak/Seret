import Testing
import Foundation
@testable import DebridCore

struct RealDebridResourceModelsTests {
    @Test func decodesTorrentListItem() throws {
        let json = #"""
        {"id":"ABC","filename":"Dune.Part.Two.2024.2160p.mkv","hash":"deadbeef",
         "bytes":25000000000,"host":"real-debrid.com","progress":100,
         "status":"downloaded","added":"2024-03-01T12:00:00.000Z",
         "links":["https://real-debrid.com/d/AAA"],"ended":"2024-03-01T12:05:00.000Z"}
        """#
        let torrent = try JSONDecoder().decode(Torrent.self, from: Data(json.utf8))
        #expect(torrent.id == "ABC")
        #expect(torrent.status == "downloaded")
        #expect(torrent.progress == 100)
        #expect(torrent.links == ["https://real-debrid.com/d/AAA"])
    }

    @Test func decodesTorrentInfoWithFiles() throws {
        let json = #"""
        {"id":"ABC","filename":"Show.S01.1080p","hash":"beef","bytes":3000,
         "progress":100,"status":"downloaded",
         "files":[
           {"id":1,"path":"/Show.S01/sample.mkv","bytes":50,"selected":0},
           {"id":2,"path":"/Show.S01/E01.mkv","bytes":2000,"selected":1},
           {"id":3,"path":"/Show.S01/E02.mkv","bytes":900,"selected":1}],
         "links":["https://real-debrid.com/d/E01","https://real-debrid.com/d/E02"]}
        """#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.files.count == 3)
        #expect(info.links.count == 2)
    }

    @Test func decodesUnrestrictedLink() throws {
        let json = #"""
        {"id":"X","filename":"movie.mkv","mimeType":"video/x-matroska",
         "filesize":24000000000,"link":"https://real-debrid.com/d/X",
         "download":"https://srv.download.real-debrid.com/d/X/movie.mkv","streamable":1}
        """#
        let link = try JSONDecoder().decode(UnrestrictedLink.self, from: Data(json.utf8))
        #expect(link.download == "https://srv.download.real-debrid.com/d/X/movie.mkv")
        #expect(link.filename == "movie.mkv")
        #expect(link.mimeType == "video/x-matroska")
    }

    @Test func pairsSelectedFilesWithLinksInOrder() {
        let info = TorrentInfo(
            id: "ABC", filename: "Show.S01", hash: "beef", bytes: 3000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/sample.mkv", bytes: 50, selected: 0),
                TorrentFile(id: 2, path: "/Show/E01.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 3, path: "/Show/E02.mkv", bytes: 900, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02"])
        let pairs = info.selectedFilesWithLinks()
        #expect(pairs.count == 2)
        #expect(pairs[0].file.id == 2)
        #expect(pairs[0].link == "https://rd/E01")
        #expect(pairs[1].file.id == 3)
        #expect(pairs[1].link == "https://rd/E02")
    }

    @Test func primaryVideoFileIsLargestSelectedVideo() {
        let info = TorrentInfo(
            id: "ABC", filename: "Movie", hash: "beef", bytes: 3000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Movie/movie.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 2, path: "/Movie/extras.mkv", bytes: 2500, selected: 0),
                TorrentFile(id: 3, path: "/Movie/readme.txt", bytes: 9, selected: 1),
            ],
            links: ["https://rd/movie", "https://rd/readme"])
        let primary = info.primaryVideoFile()
        #expect(primary?.file.id == 1)
        #expect(primary?.link == "https://rd/movie")
    }
}
