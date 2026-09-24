import Foundation

/// The head of a request libvlc sends the loopback server.
struct HTTPRequestHead: Equatable {
    let method: String
    let path: String
    /// The `Range:` header's value, if any (the name is matched case-insensitively).
    let range: String?

    /// The session a `/s/<uuid>/<file name>` path names. The file name is only for people and
    /// libvlc (the log, the extension hint); the ID alone finds the session.
    var sessionID: UUID? {
        guard path.hasPrefix("/s/") else { return nil }
        let id = path.dropFirst(3).prefix { $0 != "/" }
        return UUID(uuidString: String(id))
    }

    /// nil until the whole head (up to the blank line) has arrived.
    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let text = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1])
        range = lines.dropFirst()
            .first { $0.lowercased().hasPrefix("range:") }
            .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
    }
}

/// Response heads the loopback server sends. Always `Connection: close` — libvlc opens a new
/// connection per reposition anyway, and on loopback that costs nothing.
enum HTTPResponseHead {
    static func partial(_ range: ClosedRange<Int64>, total: Int64, contentType: String) -> Data {
        head(status: 206, lines: [
            "Content-Type: \(contentType)",
            "Content-Length: \(range.upperBound - range.lowerBound + 1)",
            "Content-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(total)",
            "Accept-Ranges: bytes",
        ])
    }

    static func whole(total: Int64, contentType: String) -> Data {
        head(status: 200, lines: [
            "Content-Type: \(contentType)",
            "Content-Length: \(total)",
            "Accept-Ranges: bytes",
        ])
    }

    static func error(_ status: Int) -> Data {
        head(status: status, lines: ["Content-Length: 0"])
    }

    private static func head(status: Int, lines: [String]) -> Data {
        let all = ["HTTP/1.1 \(status) \(reason(status))"] + lines + ["Connection: close", "", ""]
        return Data(all.joined(separator: "\r\n").utf8)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 206: "Partial Content"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 410: "Gone"
        case 416: "Range Not Satisfiable"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}
