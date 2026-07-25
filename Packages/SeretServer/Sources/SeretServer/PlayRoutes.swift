import Foundation
import Vapor
import DebridCore

struct PlayResponse: Content { let mode: String; let url: String; let session: String }

func registerPlayRoutes(_ app: Application) {
    /// Resolve a playable RD URL, then either hand it straight to the browser (direct-play) or
    /// transcode it. Accepts `?item=<libraryID>&version=<n>` (library path) or the skeleton's
    /// `?id=<torrentID>`.
    app.post("api", "play") { req async throws -> PlayResponse in
        let directURL: String
        if let itemID = try? req.query.get(String.self, at: "item") {
            let version = (try? req.query.get(Int.self, at: "version")) ?? 0
            guard let item = await req.application.library.item(id: itemID),
                  item.sources.indices.contains(version) else { throw Abort(.notFound) }
            let link = try await req.application.torrents.unrestrict(link: item.sources[version].restrictedLink)
            directURL = link.download
        } else {
            let id = try req.query.get(String.self, at: "id")
            let info = try await req.application.torrents.info(id: id)
            guard let link = try await req.application.torrents.playableURL(for: info) else {
                throw Abort(.unprocessableEntity, reason: "No playable video file in this torrent.")
            }
            directURL = link.download
        }

        // Skip ffmpeg entirely when the browser can already play the file (H.264+AAC in MP4/MOV).
        // Costs one ffprobe; saves an entire transcode. A nil probe means "transcode", which is safe.
        if let probe = await MediaProbe.probe(url: directURL), probe.decision == .direct {
            req.logger.info("direct-play (\(probe.container), \(probe.videoCodec ?? "?")/\(probe.audioCodec ?? "?"))")
            return PlayResponse(mode: "direct", url: directURL, session: "")
        }
        let session = try await req.application.transcoder.start(input: directURL)
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
