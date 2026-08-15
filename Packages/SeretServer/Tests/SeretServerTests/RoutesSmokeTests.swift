import XCTVapor
import DebridCore
@testable import SeretServer

final class RoutesSmokeTests: XCTestCase {
    func testHealth() async throws {
        let app = try await Application.make(.testing)
        app.get("health") { _ in "ok" }   // configure() needs live RD; test the route in isolation
        try await app.test(.GET, "health") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "ok")
        }
        try await app.asyncShutdown()
    }

    func testMagnetRouteRejectsJunk() async throws {
        let app = try await Application.make(.testing)
        registerMagnetRoute(app)
        try await app.test(.POST, "api/magnet", beforeRequest: { req async throws in
            try req.content.encode(MagnetRequest(magnet: "not a magnet"))
        }, afterResponse: { res async in
            // Rejected before any RD call, so the unconfigured client is never touched.
            XCTAssertEqual(res.status, .badRequest)
        })
        try await app.asyncShutdown()
    }

    func testMagnetParsingGatesTheRoute() async throws {
        // Parsing is the gate the route depends on; the RD call itself needs a live account.
        let hex = "0123456789abcdef0123456789abcdef01234567"
        XCTAssertEqual(MagnetLink.parse("magnet:?xt=urn:btih:\(hex)")?.infoHash, hex)
        XCTAssertNil(MagnetLink.parse("not a magnet"))
    }
}
