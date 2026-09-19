import Foundation
import DebridCore

/// Asks whether this device can reach SeretServer, and says who refused if it cannot.
///
/// It exists because the address is free text and nothing ever checked it. `192.168.1.179:8000`
/// instead of `:8080` produced a refused connection, which the relay reported as "Couldn't reach
/// your Seret server" — indistinguishable from a NAS that was switched off, and good for an
/// evening of reinstalling the app.
///
/// The probe runs from inside the app process on purpose. Whether a server is reachable from a
/// laptop says nothing about whether this Apple TV can reach it: cleartext rules and local network
/// permission are properties of the device, not the network.
@MainActor
@Observable
public final class ServerConnectionTest {
    public enum Result: Equatable, Sendable {
        case untested
        /// Nothing typed yet — not a failure, just nothing to check.
        case needsAddress
        case testing
        /// Carries the address it actually reached, so a stale field cannot look like a pass.
        case reachable(String)
        case failed(String)
    }

    public private(set) var result: Result = .untested

    /// A value, not a closure reading some store: the test must probe exactly the address the
    /// screen is showing, or a pass proves nothing about what the relay will post to.
    private let address: String
    private let probe: @Sendable (URL) async throws -> Void

    public init(address: String,
                probe: @escaping @Sendable (URL) async throws -> Void) {
        self.address = address
        self.probe = probe
    }

    public func run() async {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = SeretServerAddress.url(typed, path: "/health") else {
            result = .needsAddress
            return
        }

        result = .testing
        do {
            try await probe(url)
            result = .reachable(typed)
        } catch {
            result = .failed(Self.message(for: error, address: typed))
        }
    }

    /// Names the fault precisely enough to act on.
    static func message(for error: any Error, address: String) -> String {
        guard let http = error as? HTTPError else { return "Couldn't reach your Seret server" }

        switch http {
        case .status(let code, _):
            // It answered. That is a server problem, not a network one, and saying "couldn't
            // reach" would send someone to check cables.
            return "Answered \(code) — is that really your Seret server?"
        case .transport(let detail):
            if Self.looksBlocked(detail) {
                return "This device blocked the connection — Seret needs local network access"
            }
            if Self.looksRefused(detail) {
                // Something IS at that host and nothing is listening on that port. That is a
                // wrong port far more often than it is a stopped server.
                let port = address.split(separator: ":").last.map(String.init) ?? ""
                return port.isEmpty
                    ? "Connection refused — check the port"
                    : "Nothing is listening on port \(port) — check the port"
            }
            return "Couldn't reach your Seret server"
        case .decoding:
            return "Your Seret server sent something unexpected"
        }
    }

    /// The OS declining to make the call: ATS refusing cleartext, or local network access denied.
    static func looksBlocked(_ detail: String) -> Bool {
        ["-1022", "appTransportSecurityRequiresSecureConnection", "App Transport Security",
         "cleartext", "local network"]
            .contains { detail.localizedCaseInsensitiveContains($0) }
    }

    /// The host answered the TCP handshake with a refusal — reachable host, closed port.
    static func looksRefused(_ detail: String) -> Bool {
        ["-1004", "cannotConnectToHost", "Connection refused", "Could not connect to the server"]
            .contains { detail.localizedCaseInsensitiveContains($0) }
    }
}
