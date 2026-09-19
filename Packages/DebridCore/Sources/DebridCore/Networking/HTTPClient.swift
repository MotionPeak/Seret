import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest/URLResponse live here on Linux, not in Foundation
#endif

public struct HTTPClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func get<T: Decodable>(_ url: URL, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    /// Like `get`, but also returns the `HTTPURLResponse` so callers can read response
    /// headers (e.g. Trakt's `X-Pagination-Page-Count`, which is not in the body).
    public func getWithHeaders<T: Decodable>(
        _ url: URL, headers: [String: String] = [:]
    ) async throws -> (value: T, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await perform(request)
    }

    public func post<T: Decodable>(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(Self.encodeForm(form).utf8)
        return try await send(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> (T, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Cancellation is not a transport failure, and it must stay recognisable as
            // cancellation: every `catch is CancellationError` in the app was dead while this
            // rewrapped it, so callers treated "the viewer navigated away" as "the request failed"
            // and latched screens into an error or half-loaded state they could not leave.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return (try decoder.decode(T.self, from: data), http)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        try await perform(request).0
    }

    public func post<T: Decodable, Body: Encodable>(_ url: URL, json body: Body,
                                                    headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
        return try await send(request)
    }

    /// GET returning the raw response bytes (for non-JSON payloads like a subtitle file).
    public func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Cancellation is not a transport failure, and it must stay recognisable as
            // cancellation: every `catch is CancellationError` in the app was dead while this
            // rewrapped it, so callers treated "the viewer navigated away" as "the request failed"
            // and latched screens into an error or half-loaded state they could not leave.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    /// POSTs a JSON body and validates the status, discarding the response body.
    ///
    /// `post(_:json:)` decodes a reply; an endpoint that answers 200 with nothing would fail to
    /// decode and report a transport error for a call that succeeded.
    ///
    /// `encoder` is a parameter because the date strategy is not a detail: Vapor decodes dates as
    /// ISO-8601, and `JSONEncoder`'s default writes seconds since 2001. A mismatch does not fail —
    /// it files the record under the wrong date entirely.
    public func postJSON<Body: Encodable>(_ url: URL, json body: Body,
                                          headers: [String: String] = [:],
                                          encoder: JSONEncoder = JSONEncoder()) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode,
                                   body: String(decoding: data, as: UTF8.self))
        }
    }

    /// POSTs a form-urlencoded body and validates the status, discarding the response body.
    /// For endpoints that return 204 No Content (e.g. RD `selectFiles`).
    public func postForm(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(Self.encodeForm(form).utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Cancellation is not a transport failure, and it must stay recognisable as
            // cancellation: every `catch is CancellationError` in the app was dead while this
            // rewrapped it, so callers treated "the viewer navigated away" as "the request failed"
            // and latched screens into an error or half-loaded state they could not leave.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    /// Sends a `DELETE` and discards the body. Succeeds on any 2xx (RD returns 204).
    public func delete(_ url: URL, headers: [String: String] = [:]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Cancellation is not a transport failure, and it must stay recognisable as
            // cancellation: every `catch is CancellationError` in the app was dead while this
            // rewrapped it, so callers treated "the viewer navigated away" as "the request failed"
            // and latched screens into an error or half-loaded state they could not leave.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }

    /// `application/x-www-form-urlencoded` body builder. Percent-encodes keys and values.
    public static func encodeForm(_ form: [String: String]) -> String {
        form.map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }
        .sorted()
        .joined(separator: "&")
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The URL a request finally lands on, without downloading the page.
    ///
    /// URLSession follows redirects itself, so the destination is simply the response's URL. HEAD
    /// keeps it to headers — Letterboxd maps a TMDB id to a film with a 302 and the film page is
    /// ~318 KB we have no use for. A server that refuses HEAD gets one GET retry.
    ///
    /// Lives in this file because `session` is private, which in Swift is file-scoped.
    public func resolvedURL(for url: URL) async throws -> URL {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url)
            request.httpMethod = method

            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("no HTTP response resolving \(url)")
            }
            if http.statusCode == 405, method == "HEAD" { continue }
            guard (200..<300).contains(http.statusCode) else {
                throw HTTPError.status(code: http.statusCode, body: "")
            }
            return http.url ?? url
        }
        throw HTTPError.transport("HEAD and GET both refused resolving \(url)")
    }
}
