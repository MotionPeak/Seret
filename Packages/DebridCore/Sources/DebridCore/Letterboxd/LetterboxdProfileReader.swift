import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLRequest live here on Linux, not in Foundation
#endif

/// Reads one member's public film grid and watchlist.
///
/// Public pages only — no sign-in — and deliberately not a general-purpose scraper: it reads the
/// one configured username and nothing else. Pages are fetched one at a time with a delay, because
/// this is one person reading their own profile and should look like it. A whole account is about
/// seven requests.
public struct LetterboxdProfileReader: Sendable {
    private let http: HTTPClient
    private let username: String
    private let baseURL: URL
    private let pageDelay: Duration
    private let pageLimit: Int

    public init(http: HTTPClient,
                username: String,
                baseURL: URL = URL(string: "https://letterboxd.com")!,
                pageDelay: Duration = .seconds(1),
                pageLimit: Int = 50) {
        self.http = http
        self.username = username
        self.baseURL = baseURL
        self.pageDelay = pageDelay
        self.pageLimit = pageLimit
    }

    public func films() async throws -> [LetterboxdEntry] {
        try await crawl(from: "/\(username)/films/by/date/")
    }

    public func watchlist() async throws -> [LetterboxdEntry] {
        try await crawl(from: "/\(username)/watchlist/")
    }

    private func crawl(from firstPath: String) async throws -> [LetterboxdEntry] {
        var entries: [LetterboxdEntry] = []
        var path: String? = firstPath
        var fetched = 0

        while let current = path, fetched < pageLimit {
            if fetched > 0, pageDelay > .zero { try await Task.sleep(for: pageDelay) }

            // Relative resolution, not appendingPathComponent: `current` already starts with "/".
            guard let url = URL(string: current, relativeTo: baseURL)?.absoluteURL else {
                throw LetterboxdError.profileUnavailable
            }

            let data: Data
            do {
                data = try await http.data(url)
            } catch {
                throw LetterboxdError.profileUnavailable
            }
            fetched += 1

            let page = try LetterboxdProfileParser.parse(String(decoding: data, as: UTF8.self))
            entries.append(contentsOf: page.entries)
            path = page.nextPath
        }

        return entries
    }
}
