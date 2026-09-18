import Testing
import Foundation
import Vapor
@testable import SeretServer

/// A DevTools endpoint that is actually one: a `/json` target list and a WebSocket that answers
/// CDP messages. Every other test in this file's neighbourhood fakes the transport, which is
/// exactly why the transport was where every real failure lived.
private func startFakeDevTools() async throws -> Application {
    let app = try await Application.make(.testing)
    app.http.server.configuration.hostname = "127.0.0.1"
    app.http.server.configuration.port = 0

    app.get("json") { req -> Response in
        let port = req.application.http.server.shared.localAddress?.port ?? 0
        let body = """
        [{"type":"page","url":"https://letterboxd.com/film/speed/",\
        "webSocketDebuggerUrl":"ws://127.0.0.1:\(port)/devtools/page/ABC"}]
        """
        return Response(status: .ok,
                        headers: ["Content-Type": "application/json"],
                        body: .init(string: body))
    }

    app.webSocket("devtools", "page", ":id") { _, ws in
        ws.onText { socket, text in
            let sent = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            let id = (sent?["id"] as? Int) ?? -1
            let method = (sent?["method"] as? String) ?? ""
            socket.send(#"{"id":\#(id),"result":{"echoed":"\#(method)"}}"#)
        }
    }

    try await app.server.start(address: .hostname("127.0.0.1", port: 0))
    return app
}

private func stop(_ app: Application) async throws {
    await app.server.shutdown()
    try await app.asyncShutdown()
}

@Suite struct CDPRoundTripTests {
    /// Drives the real transport end to end. It caught nothing for weeks because nothing ran it:
    /// WebSocketKit keeps `onText`'s handler in a NIOLoopBoundBox and traps the process outright
    /// when it is installed off the socket's event loop, so this test crashes the runner rather
    /// than failing if that regresses.
    @Test func sendsACommandAndReadsTheReply() async throws {
        let app = try await startFakeDevTools()
        defer { Task { try? await stop(app) } }

        let port = try #require(app.http.server.shared.localAddress?.port)
        let transport = WebSocketCDPTransport(httpBase: "http://127.0.0.1:\(port)")
        let reply = try await transport.send(method: "Page.navigate", params: ["url": "about:blank"])
        #expect((reply["echoed"] as? String) == "Page.navigate")
        await transport.close()
    }

    /// Replies are matched by id, so a second command must not be handed the first one's answer.
    @Test func matchesRepliesToTheirRequests() async throws {
        let app = try await startFakeDevTools()
        defer { Task { try? await stop(app) } }

        let port = try #require(app.http.server.shared.localAddress?.port)
        let transport = WebSocketCDPTransport(httpBase: "http://127.0.0.1:\(port)")
        _ = try await transport.send(method: "Page.enable", params: [:])
        let second = try await transport.send(method: "Runtime.evaluate", params: [:])
        #expect((second["echoed"] as? String) == "Runtime.evaluate")
        await transport.close()
    }
}
