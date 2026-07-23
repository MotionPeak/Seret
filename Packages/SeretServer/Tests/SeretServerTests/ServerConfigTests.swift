import XCTest
@testable import SeretServer

final class ServerConfigTests: XCTestCase {
    func testParsesDefaultsAndRequiresToken() throws {
        let cfg = try ServerConfig.fromEnvironment(["RD_TOKEN": "abc"])
        XCTAssertEqual(cfg.rdToken, "abc")
        XCTAssertEqual(cfg.port, 8080)
        XCTAssertEqual(cfg.maxHeight, 1080)
        XCTAssertEqual(cfg.maxSessions, 2)
        XCTAssertEqual(cfg.hlsRoot, "/tmp/seret-hls")
    }

    func testMissingTokenThrows() {
        XCTAssertThrowsError(try ServerConfig.fromEnvironment([:])) { error in
            XCTAssertEqual(error as? ServerConfig.ConfigError, .missing("RD_TOKEN"))
        }
    }

    func testOverrides() throws {
        let cfg = try ServerConfig.fromEnvironment([
            "RD_TOKEN": "t", "SERET_PORT": "9000",
            "SERET_TRANSCODE_MAX_HEIGHT": "720", "SERET_MAX_SESSIONS": "1",
            "SERET_HLS_ROOT": "/data/hls",
        ])
        XCTAssertEqual(cfg.port, 9000)
        XCTAssertEqual(cfg.maxHeight, 720)
        XCTAssertEqual(cfg.maxSessions, 1)
        XCTAssertEqual(cfg.hlsRoot, "/data/hls")
    }
}
