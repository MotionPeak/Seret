import Vapor
import DebridCore

struct TorrentDTO: Content { let id: String; let filename: String }

func registerTorrentsRoutes(_ app: Application) {
    app.get("api", "torrents") { req async throws -> [TorrentDTO] in
        let list = try await req.application.torrents.allTorrents()
        return list.map { TorrentDTO(id: $0.id, filename: $0.filename) }
    }
}
