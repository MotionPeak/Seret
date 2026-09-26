import Foundation
import Testing
@testable import DebridCore

@Suite struct HTTPMessagesTests {
    private func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func parsesLibvlcsRequest() throws {
        let id = UUID()
        let raw = "GET /s/\(id.uuidString) HTTP/1.1\r\nHost: 127.0.0.1:5000\r\nAccept: */*\r\n"
            + "User-Agent: VLC/4.0.0-dev LibVLC/4.0.0-dev\r\nrange: bytes=1048576-\r\n\r\n"
        let head = try #require(HTTPRequestHead(Data(raw.utf8)))
        #expect(head.method == "GET")
        #expect(head.sessionID == id)
        #expect(head.range == "bytes=1048576-")                 // header name matched case-insensitively
    }

    @Test func theFileNameAfterTheSessionIsIgnored() throws {
        // The loopback URL ends in the film's file name, for the log and libvlc's extension hint.
        let id = UUID()
        let raw = "GET /s/\(id.uuidString)/Goodfellas%201990.mkv HTTP/1.1\r\nHost: a\r\n\r\n"
        #expect(try #require(HTTPRequestHead(Data(raw.utf8))).sessionID == id)
    }

    @Test func anIncompleteHeadIsNotParsed() {
        #expect(HTTPRequestHead(Data("GET /s/x HTTP/1.1\r\nHost: a\r\n".utf8)) == nil)
    }

    @Test func aPathThatIsNotASessionHasNoID() throws {
        let head = try #require(HTTPRequestHead(Data("GET /favicon.ico HTTP/1.1\r\n\r\n".utf8)))
        #expect(head.sessionID == nil)
    }

    @Test func aPartialResponseCarriesTheExactRange() {
        let t = text(HTTPResponseHead.partial(40...99, total: 100, contentType: "application/force-download"))
        #expect(t.hasPrefix("HTTP/1.1 206 Partial Content\r\n"))
        #expect(t.contains("\r\nContent-Length: 60\r\n"))
        #expect(t.contains("\r\nContent-Range: bytes 40-99/100\r\n"))
        #expect(t.contains("\r\nAccept-Ranges: bytes\r\n"))
        #expect(t.contains("\r\nConnection: close\r\n"))
        #expect(t.hasSuffix("\r\n\r\n"))
    }

    @Test func aWholeResponseIs200() {
        let t = text(HTTPResponseHead.whole(total: 100, contentType: "video/x-matroska"))
        #expect(t.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(t.contains("\r\nContent-Length: 100\r\n"))
    }

    @Test func anErrorHasNoBody() {
        let t = text(HTTPResponseHead.error(416))
        #expect(t.hasPrefix("HTTP/1.1 416 Range Not Satisfiable\r\n"))
        #expect(t.contains("\r\nContent-Length: 0\r\n"))
        #expect(text(HTTPResponseHead.error(403)).hasPrefix("HTTP/1.1 403 Forbidden\r\n"))
    }
}
