import Vapor
import DebridCore

/// Wires the Vapor application: server binding, RD client, library, transcoder, and routes.
func configure(_ app: Application, config: ServerConfig) async throws {
    app.http.server.configuration.port = config.port
    app.http.server.configuration.hostname = "0.0.0.0"
    app.torrents = try await makeTorrentsClient(rdToken: config.rdToken)
    app.transcoder = TranscodeManager(root: config.hlsRoot,
                                      maxHeight: config.maxHeight,
                                      maxSessions: config.maxSessions)
    let tmdb = TMDBClient(apiKey: config.tmdbAPIKey)
    app.tmdb = tmdb
    app.ratings = config.omdbAPIKey.isEmpty ? nil : OMDbClient(apiKey: config.omdbAPIKey)
    if config.omdbAPIKey.isEmpty {
        app.logger.notice("OMDB_API_KEY is empty — the detail page ratings row is disabled.")
    }
    app.library = ServerLibrary(
        torrents: app.torrents,
        enricher: MetadataEnricher(tmdb: tmdb))

    let sessions = SessionStore()
    app.middleware.use(AuthMiddleware(password: config.webPassword, sessions: sessions))
    if config.webPassword.isEmpty {
        app.logger.warning("SERET_WEB_PASSWORD is empty — the API is unauthenticated (LAN/Tailscale only!)")
    }

    app.get("health") { _ in "ok" }
    registerAuthRoutes(app, password: config.webPassword, sessions: sessions)
    registerTorrentsRoutes(app)
    registerLibraryRoutes(app)
    registerDetailRoutes(app)
    registerPlayRoutes(app)
    registerPlayerPages(app)

    // NOTE: deliberately no boot-time warm-up. Building the library at startup means any failure
    // in that path kills the process before it can serve anything, and `--restart unless-stopped`
    // turns that into an endless crash-loop with no way to reach /health or read the error. The
    // library builds lazily on the first /api/library request instead.
}
