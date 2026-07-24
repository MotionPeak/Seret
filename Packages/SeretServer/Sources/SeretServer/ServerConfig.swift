import Foundation

/// Server configuration, parsed once at boot from environment variables. `RD_TOKEN` and
/// `TMDB_API_KEY` are required (the library is TMDB-organized); the rest have sensible defaults.
/// Leaving `SERET_WEB_PASSWORD` empty disables the auth gate (fine on a LAN/Tailscale-only host).
struct ServerConfig: Sendable {
    let rdToken: String
    let tmdbAPIKey: String
    let webPassword: String
    let port: Int
    let maxHeight: Int
    let maxSessions: Int
    let hlsRoot: String

    enum ConfigError: Error, Equatable { case missing(String) }

    static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ServerConfig {
        func require(_ key: String) throws -> String {
            guard let v = env[key], !v.isEmpty else { throw ConfigError.missing(key) }
            return v
        }
        return ServerConfig(
            rdToken: try require("RD_TOKEN"),
            tmdbAPIKey: try require("TMDB_API_KEY"),
            webPassword: env["SERET_WEB_PASSWORD"] ?? "",
            port: Int(env["SERET_PORT"] ?? "") ?? 8080,
            maxHeight: Int(env["SERET_TRANSCODE_MAX_HEIGHT"] ?? "") ?? 1080,
            maxSessions: Int(env["SERET_MAX_SESSIONS"] ?? "") ?? 2,
            hlsRoot: env["SERET_HLS_ROOT"] ?? "/tmp/seret-hls"
        )
    }
}
