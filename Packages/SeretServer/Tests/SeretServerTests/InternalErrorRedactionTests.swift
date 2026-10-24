import XCTVapor
import DebridCore
@testable import SeretServer

/// Vapor's default error middleware answers a non-`Abort` error with `String(describing: error)`
/// outside production, and logs the same. An internal error can carry a URL with a key in it
/// (TorBox's `requestdl`), so the server must answer — and log — something generic instead.
final class InternalErrorRedactionTests: XCTestCase {
    struct LeakyError: Error, CustomStringConvertible {
        var description: String { "failed fetching https://api.torbox.app/v1/api/torrents/requestdl?token=SECRETKEY" }
    }

    func testInternalErrorIsNotEchoed() async throws {
        let app = try await Application.make(.development)
        app.middleware.use(InternalErrorRedactingMiddleware())
        app.get("boom") { _ -> String in throw LeakyError() }
        try await app.test(.GET, "boom") { res async in
            XCTAssertEqual(res.status, .internalServerError)
            XCTAssertFalse(res.body.string.contains("SECRETKEY"))
            XCTAssertFalse(res.body.string.contains("requestdl"))
        }
        try await app.asyncShutdown()
    }

    func testAbortReasonStillReachesTheBrowser() async throws {
        let app = try await Application.make(.development)
        app.middleware.use(InternalErrorRedactingMiddleware())
        app.get("nope") { _ -> String in throw Abort(.unprocessableEntity, reason: "No playable video file.") }
        try await app.test(.GET, "nope") { res async in
            XCTAssertEqual(res.status, .unprocessableEntity)
            XCTAssertTrue(res.body.string.contains("No playable video file."))
        }
        try await app.asyncShutdown()
    }
}
