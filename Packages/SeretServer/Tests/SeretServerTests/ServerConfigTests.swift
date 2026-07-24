import XCTest
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

    func testMissingRDTokenThrows() {
        XCTAssertThrowsError(try ServerConfig.fromEnvironment(["TMDB_API_KEY": "k"])) { error in
            XCTAssertEqual(error as? ServerConfig.ConfigError, .missing("RD_TOKEN"))
        }
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
