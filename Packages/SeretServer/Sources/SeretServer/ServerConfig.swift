import Foundation
import DebridCore

/// Server configuration, parsed once at boot from environment variables. `TMDB_API_KEY` is required
/// (the library is TMDB-organized), and so is at least one of `RD_TOKEN` / `TORBOX_API_KEY`; the
/// rest have sensible defaults.
/// Leaving `SERET_WEB_PASSWORD` empty disables the auth gate (fine on a LAN/Tailscale-only host).
struct ServerConfig: Sendable {
    /// Real-Debrid API token (real-debrid.com/apitoken). `nil` when this server has no RD account.
    let rdToken: String?
    /// TorBox API key (torbox.app/settings). `nil` when this server has no TorBox account.
    let torBoxAPIKey: String?
    /// Which account an add (magnet) goes to when both are configured. `nil` = no preference, so
    /// the composite client uses the first signed-in account (Real-Debrid, then TorBox).
    let addTarget: DebridProvider?
    let tmdbAPIKey: String
    /// Optional OMDb key (omdbapi.com) for IMDb/Rotten Tomatoes/Metacritic ratings on the detail
    /// page. Empty disables the ratings row by design — same graceful-degradation pattern as subs.
    let omdbAPIKey: String
    /// Optional OpenSubtitles API key. It matches Hebrew subtitles to each version on the title
    /// page; empty turns matching off (built-in detection still runs).
    let openSubtitlesAPIKey: String
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
        /// A variable set to the empty string (how a compose file leaves one "unset") is absent.
        func optional(_ key: String) -> String? {
            guard let v = env[key], !v.isEmpty else { return nil }
            return v
        }
        let rd = optional("RD_TOKEN")
        let torBox = optional("TORBOX_API_KEY")
        guard rd != nil || torBox != nil else {
            throw ConfigError.missing("RD_TOKEN or TORBOX_API_KEY")
        }
        return ServerConfig(
            rdToken: rd,
            torBoxAPIKey: torBox,
            // An unrecognised value is ignored rather than fatal: a typo must not turn into a
            // crash-looping container (see the note in `configure`).
            addTarget: optional("DEBRID_ADD_TARGET").flatMap { DebridProvider(rawValue: $0) },
            tmdbAPIKey: try require("TMDB_API_KEY"),
            omdbAPIKey: env["OMDB_API_KEY"] ?? "",
            openSubtitlesAPIKey: env["OPENSUBTITLES_API_KEY"] ?? "",
            webPassword: env["SERET_WEB_PASSWORD"] ?? "",
            port: Int(env["SERET_PORT"] ?? "") ?? 8080,
            maxHeight: Int(env["SERET_TRANSCODE_MAX_HEIGHT"] ?? "") ?? 1080,
            maxSessions: Int(env["SERET_MAX_SESSIONS"] ?? "") ?? 2,
            hlsRoot: env["SERET_HLS_ROOT"] ?? "/tmp/seret-hls"
        )
    }
}
