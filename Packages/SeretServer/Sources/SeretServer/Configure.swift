import Vapor

/// Wires the Vapor application: server binding + routes. Async because building the RD client
/// (Task 4) hits the network at boot.
func configure(_ app: Application, config: ServerConfig) async throws {
    app.http.server.configuration.port = config.port
    app.http.server.configuration.hostname = "0.0.0.0"
    app.get("health") { _ in "ok" }
}
