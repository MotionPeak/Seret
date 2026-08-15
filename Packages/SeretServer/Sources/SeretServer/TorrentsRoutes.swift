import Vapor
import DebridCore

struct TorrentDTO: Content { let id: String; let filename: String }

struct MagnetRequest: Content {
    let magnet: String
    var contentKey: String?
    var tmdbID: Int?
    var title: String?
}

struct MagnetResponse: Content { let torrentID: String; let infoHash: String }

func registerTorrentsRoutes(_ app: Application) {
    app.get("api", "torrents") { req async throws -> [TorrentDTO] in
        let list = try await req.application.torrents.allTorrents()
        return list.map { TorrentDTO(id: $0.id, filename: $0.filename) }
    }
    registerMagnetRoute(app)
}

/// `POST /api/magnet` — accepts a pasted magnet link or bare infohash and hands it to RD.
/// Split out from `registerTorrentsRoutes` so a test can register it without the RD wiring
/// that `configure()` requires.
func registerMagnetRoute(_ app: Application) {
    app.post("api", "magnet") { req async throws -> MagnetResponse in
        let body = try req.content.decode(MagnetRequest.self)
        // Parsing gates the RD call, so a typo costs nothing and cannot leave a junk torrent
        // on the account.
        guard let link = MagnetLink.parse(body.magnet) else {
            throw Abort(.badRequest, reason: "That isn't a magnet link or infohash.")
        }
        let info = try await req.application.torrents.addForDownload(magnetHash: link.infoHash)
        return MagnetResponse(torrentID: info.id, infoHash: link.infoHash)
    }
}
