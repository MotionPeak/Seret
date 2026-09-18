import Testing
import Foundation
import NIOCore
import NIOPosix
@testable import SeretServer

/// Answers one request with fixed bytes, so a response can be written exactly as Chrome writes one.
private final class CannedResponse: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let response: String
    init(_ response: String) { self.response = response }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
        buffer.writeString(response)
        // The channel, not the context: a ChannelHandlerContext is not Sendable and capturing one
        // in the completion closure warns on Linux.
        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(buffer)).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}

/// A DevTools endpoint, headers and all. `separator` is the whole point: Chrome writes
/// `Content-Length:404` with no space, which is legal and which almost nothing else does.
private func devToolsStub(separator: String) throws -> (Channel, Int) {
    let body = """
    [{"type":"page","url":"https://letterboxd.com/film/speed/",\
    "webSocketDebuggerUrl":"ws://127.0.0.1:9223/devtools/page/ABC"}]
    """
    let response = "HTTP/1.1 200 OK\r\n"
        + "Content-Security-Policy\(separator)frame-ancestors 'none'\r\n"
        + "Content-Length\(separator)\(body.utf8.count)\r\n"
        + "Content-Type\(separator)application/json; charset=UTF-8\r\n\r\n"
        + body

    let channel = try ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .serverChannelOption(.backlog, value: 8)
        .childChannelInitializer { $0.pipeline.addHandler(CannedResponse(response)) }
        .bind(host: "127.0.0.1", port: 0)
        .wait()
    return (channel, channel.localAddress!.port!)
}

@Suite struct CDPTargetDiscoveryTests {
    /// Chrome's DevTools omits the space after every header colon, and swift-corelibs-foundation's
    /// URLSession refuses to parse that - it throws "Failed writing header" and the browser might
    /// as well be down. Measured against the real endpoint on the NAS.
    @Test func readsTargetsFromHeadersWrittenTheWayChromeWritesThem() async throws {
        let (server, port) = try devToolsStub(separator: ":")
        defer { server.close(promise: nil) }

        let transport = WebSocketCDPTransport(httpBase: "http://127.0.0.1:\(port)")
        #expect(try await transport.pageWebSocketURL() == "ws://127.0.0.1:9223/devtools/page/ABC")
    }

    @Test func andStillReadsOrdinaryOnes() async throws {
        let (server, port) = try devToolsStub(separator: ": ")
        defer { server.close(promise: nil) }

        let transport = WebSocketCDPTransport(httpBase: "http://127.0.0.1:\(port)")
        #expect(try await transport.pageWebSocketURL() == "ws://127.0.0.1:9223/devtools/page/ABC")
    }
}
