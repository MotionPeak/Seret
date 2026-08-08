import Foundation
import Network
import Observation

/// A single-purpose HTTP server that lets the viewer type a password on their phone instead of on
/// a TV remote.
///
/// Why this exists at all: OpenSubtitles has no device-code flow. Real-Debrid does — you show a
/// code, the user approves it on another device, and the token arrives — but OpenSubtitles only
/// takes a username and password, so there is nothing to poll for. The only way to move the typing
/// to a phone is to be the thing the phone types into.
///
/// So the Apple TV serves one page on the local network and the QR is simply its address. The
/// credentials go phone → TV over the LAN and nowhere else: no relay, no third party, nothing that
/// keeps working after this screen closes. The listener is started when the pairing view appears
/// and stopped when it leaves, so the app is not running a server in the background.
///
/// Plain HTTP, deliberately: a self-signed certificate would make every phone show a security
/// warning on the page we are asking them to type a password into, which trains exactly the wrong
/// instinct. The exposure is one port, on the viewer's own network, for as long as the screen is
/// open. `submissionToken` also has to be echoed back, so a stray request from something else on
/// the network cannot post credentials at us.
/// `@Observable` is load-bearing, not decoration: the QR cannot be drawn until the listener is
/// ready and `address` is filled in asynchronously, so a plain class leaves the view showing
/// "Preparing…" for ever — the address arrives and nothing re-renders.
@MainActor
@Observable
final class LocalPairingServer {

    /// What the phone submitted.
    struct Credentials: Equatable {
        let username: String
        let password: String
    }

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let onReceive: (Credentials) -> Void
    /// Included in the served form and required back on POST — see the type doc.
    private let submissionToken = UUID().uuidString

    /// The address to encode in the QR, e.g. `http://192.168.1.42:8099`. nil until `start()`.
    private(set) var address: String?

    init(onReceive: @escaping (Credentials) -> Void) {
        self.onReceive = onReceive
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        // Port 0 asks the system for a free one, so a second launch can never collide with a
        // lingering socket from the last.
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            Task { @MainActor in
                guard let self, let port = self.listener?.port else { return }
                self.address = Self.localAddress(port: port.rawValue)
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections { connection.cancel() }
        connections = []
        address = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    /// Read until the whole request is in hand.
    ///
    /// A POST body can arrive in a separate TCP segment from its headers, so a single read is not
    /// enough — reading once and parsing is how this kind of server silently loses every password
    /// longer than the first packet. Keep reading until `Content-Length` is satisfied.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil else { self.close(connection); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer), request.isComplete {
                    self.respond(to: request, on: connection)
                } else if isComplete {
                    self.close(connection)
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let body: String
        if request.method == "POST", request.path == "/login" {
            let fields = Self.formFields(request.body)
            if fields["token"] == submissionToken,
               let username = fields["username"], !username.isEmpty,
               let password = fields["password"], !password.isEmpty {
                onReceive(Credentials(username: username, password: password))
                body = Self.donePage
            } else {
                body = Self.formPage(token: submissionToken, error: "Enter both a username and a password.")
            }
        } else {
            body = Self.formPage(token: submissionToken, error: nil)
        }
        send(body, on: connection)
    }

    private func send(_ html: String, on connection: NWConnection) {
        let data = Data(html.utf8)
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(data.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        connection.send(content: Data(head.utf8) + data,
                        completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(connection) }
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    // MARK: - Parsing

    /// `a=b&c=d` with percent-decoding, including `+` for space, which URLComponents does NOT undo
    /// for form bodies — a password containing a space would otherwise arrive mangled.
    static func formFields(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2 else { continue }
            let key = decode(String(halves[0]))
            fields[key] = decode(String(halves[1]))
        }
        return fields
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    /// This device's address on the LAN. Wi-Fi first, then wired — an Apple TV can be either.
    static func localAddress(port: UInt16) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var best: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == "en0" { return "http://\(address):\(port)" }   // Wi-Fi wins outright
            best = "http://\(address):\(port)"
        }
        return best
    }
}

/// The smallest HTTP request parse that is still correct about bodies arriving late.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: String
    /// False while a declared `Content-Length` has not fully arrived yet.
    let isComplete: Bool

    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let head = String(text[text.startIndex..<headerEnd.lowerBound])
        let lines = head.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        guard request.count >= 2 else { return nil }
        method = String(request[0])
        path = String(request[1])
        let declared = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let received = String(text[headerEnd.upperBound...])
        body = received
        isComplete = received.utf8.count >= declared
    }
}

// MARK: - The page

private extension LocalPairingServer {

    /// Styled to look like the app, because a plain browser form asking for a password is exactly
    /// what a phishing page looks like — it should be obvious this came from Seret on the TV.
    static func page(_ contents: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Seret — OpenSubtitles</title><style>
        :root{color-scheme:dark}
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
             background:#0b0b0d;color:#f5f5f7;
             font:16px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif}
        .card{width:min(420px,92vw);padding:32px 28px;background:#17171b;border-radius:20px;
              box-shadow:0 20px 60px rgba(0,0,0,.5)}
        h1{margin:0 0 6px;font-size:22px;letter-spacing:-.01em}
        p{margin:0 0 24px;color:#a1a1a8;font-size:15px}
        label{display:block;margin:0 0 6px;font-size:13px;color:#a1a1a8}
        input{width:100%;box-sizing:border-box;padding:14px;margin:0 0 18px;font-size:17px;
              color:#f5f5f7;background:#242429;border:1px solid #34343b;border-radius:12px}
        input:focus{outline:none;border-color:#f5c518}
        button{width:100%;padding:15px;font-size:17px;font-weight:600;color:#1a1a1a;
               background:#f5c518;border:0;border-radius:12px}
        .err{margin:0 0 18px;padding:12px 14px;border-radius:10px;font-size:14px;
             background:rgba(255,69,58,.12);color:#ff8a80}
        .ok{font-size:40px;text-align:center;margin:0 0 12px}
        </style></head><body><div class="card">\(contents)</div></body></html>
        """
    }

    static func formPage(token: String, error: String?) -> String {
        page("""
        <h1>Sign in to OpenSubtitles</h1>
        <p>This goes straight to your Apple TV over your home network.</p>
        \(error.map { "<div class=\"err\">\($0)</div>" } ?? "")
        <form method="post" action="/login">
          <input type="hidden" name="token" value="\(token)">
          <label for="u">Username</label>
          <input id="u" name="username" autocapitalize="none" autocorrect="off" autocomplete="username">
          <label for="p">Password</label>
          <input id="p" name="password" type="password" autocomplete="current-password">
          <button type="submit">Sign in</button>
        </form>
        """)
    }

    static var donePage: String {
        page("""
        <div class="ok">\u{2713}</div>
        <h1 style="text-align:center">Sent to your Apple TV</h1>
        <p style="text-align:center;margin:0">You can close this page.</p>
        """)
    }
}
