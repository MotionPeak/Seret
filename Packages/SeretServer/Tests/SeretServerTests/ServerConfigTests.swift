import XCTest
import DebridCore
@testable import SeretServer

final class ServerConfigTests: XCTestCase {
    /// The minimum env a real deployment needs.
    private let required = ["RD_TOKEN": "abc", "TMDB_API_KEY": "tmdb-key"]

    func testParsesDefaults() throws {
        let cfg = try ServerConfig.fromEnvironment(required)
        XCTAssertEqual(cfg.rdToken, "abc")
        XCTAssertEqual(cfg.tmdbAPIKey, "tmdb-key")
        XCTAssertEqual(cfg.port, 8080)
        XCTAssertEqual(cfg.maxHeight, 1080)
        XCTAssertEqual(cfg.maxSessions, 2)
        XCTAssertEqual(cfg.hlsRoot, "/tmp/seret-hls")
        XCTAssertEqual(cfg.webPassword, "", "empty password disables the gate by design")
    }

    func testConfigRequiresAtLeastOneProvider() {
        XCTAssertThrowsError(try ServerConfig.fromEnvironment(["TMDB_API_KEY": "k"])) { error in
            XCTAssertEqual(error as? ServerConfig.ConfigError, .missing("RD_TOKEN or TORBOX_API_KEY"))
        }
        // Set-but-empty is how a compose file leaves a variable unset; it is not a key.
        XCTAssertThrowsError(try ServerConfig.fromEnvironment(
            ["TMDB_API_KEY": "k", "RD_TOKEN": "", "TORBOX_API_KEY": ""])) { error in
            XCTAssertEqual(error as? ServerConfig.ConfigError, .missing("RD_TOKEN or TORBOX_API_KEY"))
        }
    }

    func testConfigAcceptsTorBoxOnly() throws {
        let cfg = try ServerConfig.fromEnvironment(["TMDB_API_KEY": "k", "TORBOX_API_KEY": "tb-key"])
        XCTAssertEqual(cfg.torBoxAPIKey, "tb-key")
        XCTAssertNil(cfg.rdToken)
        XCTAssertNil(cfg.addTarget)
    }

    func testConfigAcceptsRealDebridOnly() throws {
        let cfg = try ServerConfig.fromEnvironment(required)
        XCTAssertEqual(cfg.rdToken, "abc")
        XCTAssertNil(cfg.torBoxAPIKey)
    }

    func testConfigReadsAddTarget() throws {
        let both = required.merging(["TORBOX_API_KEY": "tb"]) { _, new in new }
        XCTAssertEqual(try ServerConfig.fromEnvironment(
            both.merging(["DEBRID_ADD_TARGET": "torBox"]) { _, new in new }).addTarget, .torBox)
        XCTAssertEqual(try ServerConfig.fromEnvironment(
            both.merging(["DEBRID_ADD_TARGET": "realDebrid"]) { _, new in new }).addTarget, .realDebrid)
        XCTAssertNil(try ServerConfig.fromEnvironment(both).addTarget)
    }

    /// A typo must not crash-loop the container (`--restart unless-stopped`); it falls back to
    /// "no preference", which the composite client resolves to the first signed-in account.
    func testUnrecognisedAddTargetIsIgnored() throws {
        let cfg = try ServerConfig.fromEnvironment(
            required.merging(["DEBRID_ADD_TARGET": "TorBoks"]) { _, new in new })
        XCTAssertNil(cfg.addTarget)
    }

    func testMissingTMDBKeyThrows() {
        XCTAssertThrowsError(try ServerConfig.fromEnvironment(["RD_TOKEN": "t"])) { error in
            XCTAssertEqual(error as? ServerConfig.ConfigError, .missing("TMDB_API_KEY"))
        }
    }

    func testOverrides() throws {
        let cfg = try ServerConfig.fromEnvironment(required.merging([
            "SERET_PORT": "9000",
            "SERET_TRANSCODE_MAX_HEIGHT": "720",
            "SERET_MAX_SESSIONS": "1",
            "SERET_HLS_ROOT": "/data/hls",
            "SERET_WEB_PASSWORD": "hunter2",
        ]) { _, new in new })
        XCTAssertEqual(cfg.port, 9000)
        XCTAssertEqual(cfg.maxHeight, 720)
        XCTAssertEqual(cfg.maxSessions, 1)
        XCTAssertEqual(cfg.hlsRoot, "/data/hls")
        XCTAssertEqual(cfg.webPassword, "hunter2")
    }
}
