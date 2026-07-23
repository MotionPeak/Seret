import XCTVapor
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
}
