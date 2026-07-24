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
    app.library = ServerLibrary(
        torrents: app.torrents,
        enricher: MetadataEnricher(tmdb: TMDBClient(apiKey: config.tmdbAPIKey)))

    app.get("health") { _ in "ok" }
    registerTorrentsRoutes(app)
    registerLibraryRoutes(app)
    registerPlayRoutes(app)
    registerPlayerPages(app)

    // Warm the library at boot so the first page load isn't paying for the whole RD+TMDB pass.
    let library = app.library
    Task { try? await library.refresh() }
}
