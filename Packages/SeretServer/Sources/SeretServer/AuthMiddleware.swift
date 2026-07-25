import Foundation
import Vapor

/// Issued session tokens, in memory. A restart simply means signing in again — acceptable for a
/// single-user LAN/Tailscale deployment, and it keeps secrets off disk.
actor SessionStore {
    private var tokens: Set<String> = []

    func issue() -> String {
        let token = UUID().uuidString + UUID().uuidString
        tokens.insert(token)
        return token
    }

    func isValid(_ token: String) -> Bool { tokens.contains(token) }
    func revoke(_ token: String) { tokens.remove(token) }
}

/// Guards `/api/*` and `/hls/*` behind a shared password.
///
/// An empty `SERET_WEB_PASSWORD` disables the gate entirely — the intended setup when the host is
/// only reachable on the LAN or over Tailscale, where the network is the real boundary.
struct AuthMiddleware: AsyncMiddleware {
    static let cookieName = "seret_session"

    let password: String
    let sessions: SessionStore

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard !password.isEmpty else { return try await next.respond(to: request) }

        let path = request.url.path
        let gated = path.hasPrefix("/api/") || path.hasPrefix("/hls/")
        let isLogin = path == "/api/session"
        guard gated, !isLogin else { return try await next.respond(to: request) }

        if let token = request.cookies[Self.cookieName]?.string, await sessions.isValid(token) {
            return try await next.respond(to: request)
        }
        throw Abort(.unauthorized)
    }
}

struct LoginBody: Content { let password: String }

func registerAuthRoutes(_ app: Application, password: String, sessions: SessionStore) {
    app.post("api", "session") { req async throws -> Response in
        let body = try req.content.decode(LoginBody.self)
        guard !password.isEmpty, body.password == password else { throw Abort(.unauthorized) }
        let token = await sessions.issue()
        let res = Response(status: .ok)
        res.cookies[AuthMiddleware.cookieName] = HTTPCookies.Value(
            string: token, isSecure: false, isHTTPOnly: true, sameSite: .lax)
        return res
    }

    // Whether a gate is even configured — lets the UI skip the login screen entirely.
    app.get("api", "auth") { _ async -> [String: Bool] in ["required": !password.isEmpty] }
}
