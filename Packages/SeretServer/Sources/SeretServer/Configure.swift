import Vapor

/// Wires the Vapor application: server binding, RD client, transcoder, and routes.
func configure(_ app: Application, config: ServerConfig) async throws {
    app.http.server.configuration.port = config.port
    app.http.server.configuration.hostname = "0.0.0.0"
    app.torrents = try await makeTorrentsClient(rdToken: config.rdToken)
    app.transcoder = TranscodeManager(root: config.hlsRoot,
                                      maxHeight: config.maxHeight,
                                      maxSessions: config.maxSessions)
    app.get("health") { _ in "ok" }
    registerTorrentsRoutes(app)
    registerPlayRoutes(app)
    registerPlayerPages(app)
}
