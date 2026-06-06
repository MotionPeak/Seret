import Foundation

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

    public func post<T: Decodable>(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(Self.encodeForm(form).utf8)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
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
}
