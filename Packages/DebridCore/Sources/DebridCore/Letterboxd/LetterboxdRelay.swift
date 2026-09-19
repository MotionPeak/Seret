import Foundation

/// Hands one write to SeretServer, which owns the browser that can actually reach Letterboxd.
///
/// A seam, because the coordinator's tests must not touch the network and cannot nest under
/// `MockTests` — they need their own fakes, and a suite cannot have two serialized parents.
public protocol LetterboxdRelaying: Sendable {
    func send(_ write: LetterboxdWrite) async throws
}

/// The app never writes to Letterboxd itself and never tries: Cloudflare refuses every non-browser
/// client, measured with a full valid session and Chrome's exact User-Agent. It hands the server an
/// intent; the server drives a real browser.
public struct HTTPLetterboxdRelay: LetterboxdRelaying {
    private struct Payload: Encodable {
        let tmdbID: Int
        let rating: Int?
        let watchedAt: Date?
        let rewatch: Bool
    }

    private let http: HTTPClient
    private let baseURL: URL

    public init(http: HTTPClient = HTTPClient(), baseURL: URL) {
        self.http = http
        self.baseURL = baseURL
    }

    public func send(_ write: LetterboxdWrite) async throws {
        let url = baseURL.appendingPathComponent("api/letterboxd/diary")
        let payload = Payload(tmdbID: write.tmdbID, rating: write.rating,
                              watchedAt: write.watchedAt, rewatch: write.rewatch)

        // ISO-8601 because that is what Vapor's default content configuration decodes. The default
        // strategy would send seconds since 2001 and file the entry in the wrong year.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            try await http.postJSON(url, json: payload, encoder: encoder)
        } catch let error as HTTPError {
            throw Self.letterboxdError(for: error)
        }
    }

    /// The server tells us which of three different problems it hit; keeping them apart is the
    /// whole point of it doing so. A queue that retries a dead session forever, or gives up on a
    /// Synology that is merely switched off, is the failure this avoids.
    static func letterboxdError(for error: HTTPError) -> LetterboxdError {
        switch error {
        case .status(401, _), .status(403, _):
            return .notAuthenticated
        case .status(503, _):
            return .challenged
        case .status(404, _):
            return .filmNotFound
        case .status(let code, let body):
            return .transient("server returned \(code)\(body.isEmpty ? "" : ": \(body)")")
        case .transport(let message):
            return .transient(message)
        case .decoding(let message):
            return .transient(message)
        }
    }
}
