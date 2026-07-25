import XCTVapor
@testable import SeretServer

final class AuthTests: XCTestCase {
    /// Builds a tiny app with the gate in front of a stand-in protected route.
    private func makeApp(password: String) async throws -> (Application, SessionStore) {
        let app = try await Application.make(.testing)
        let sessions = SessionStore()
        app.middleware.use(AuthMiddleware(password: password, sessions: sessions))
        registerAuthRoutes(app, password: password, sessions: sessions)
        app.get("api", "library") { _ in "secret" }
        app.get("hls", "x", "index.m3u8") { _ in "manifest" }
        app.get("openpage") { _ in "public" }
        return (app, sessions)
    }

    func testGatedRoutesRejectWithoutCookie() async throws {
        let (app, _) = try await makeApp(password: "pw")
        try await app.test(.GET, "api/library") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.test(.GET, "hls/x/index.m3u8") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.asyncShutdown()
    }

    func testNonAPIPagesAreNotGated() async throws {
        let (app, _) = try await makeApp(password: "pw")
        try await app.test(.GET, "openpage") { res async in
            XCTAssertEqual(res.status, .ok)
        }
        try await app.asyncShutdown()
    }

    func testWrongPasswordIsRejected() async throws {
        let (app, _) = try await makeApp(password: "pw")
        try await app.test(.POST, "api/session", beforeRequest: { req async throws in
            try req.content.encode(LoginBody(password: "nope"))
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
        try await app.asyncShutdown()
    }

    func testCorrectPasswordIssuesCookieThatUnlocksTheAPI() async throws {
        let (app, _) = try await makeApp(password: "pw")
        var cookie: HTTPCookies.Value?
        try await app.test(.POST, "api/session", beforeRequest: { req async throws in
            try req.content.encode(LoginBody(password: "pw"))
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            cookie = res.headers.setCookie?[AuthMiddleware.cookieName]
            XCTAssertNotNil(cookie)
        })
        let token = try XCTUnwrap(cookie).string
        try await app.test(.GET, "api/library", beforeRequest: { req async throws in
            req.headers.cookie = [AuthMiddleware.cookieName: .init(string: token)]
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "secret")
        })
        try await app.asyncShutdown()
    }

    func testEmptyPasswordDisablesTheGate() async throws {
        let (app, _) = try await makeApp(password: "")
        try await app.test(.GET, "api/library") { res async in
            XCTAssertEqual(res.status, .ok)
        }
        try await app.asyncShutdown()
    }
}
