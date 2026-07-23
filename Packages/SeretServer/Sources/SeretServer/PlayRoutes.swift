import Foundation
import Vapor
import DebridCore

struct PlayResponse: Content { let mode: String; let url: String; let session: String }

func registerPlayRoutes(_ app: Application) {
    // Unrestrict the torrent's primary video file → start a transcode → return the manifest URL.
    app.post("api", "play") { req async throws -> PlayResponse in
        let id = try req.query.get(String.self, at: "id")
        let info = try await req.application.torrents.info(id: id)
        guard let link = try await req.application.torrents.playableURL(for: info) else {
            throw Abort(.unprocessableEntity, reason: "No playable video file in this torrent.")
        }
        let session = try await req.application.transcoder.start(input: link.download)
        return PlayResponse(mode: "hls", url: "/hls/\(session)/index.m3u8", session: session)
    }

    // Serve HLS manifest + segments ffmpeg is writing.
    app.get("hls", ":session", "**") { req async throws -> Response in
        let session = try req.parameters.require("session")
        let rel = req.parameters.getCatchall().joined(separator: "/")
        guard let url = await req.application.transcoder.fileURL(session: session, relativePath: rel),
              FileManager.default.fileExists(atPath: url.path) else {
            throw Abort(.notFound)
        }
        return try await req.fileio.asyncStreamFile(at: url.path)
    }

    app.post("api", "play", ":session", "stop") { req async throws -> HTTPStatus in
        await req.application.transcoder.stop(session: try req.parameters.require("session"))
        return .ok
    }
}
