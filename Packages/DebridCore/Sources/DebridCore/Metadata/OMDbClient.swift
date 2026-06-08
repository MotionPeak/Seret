import Foundation

/// Looks up external ratings (IMDb / Rotten Tomatoes / Metacritic) for a title by its IMDb id
/// via OMDb (`https://www.omdbapi.com/?apikey=…&i=tt…`). The key is injected; tests mock the
/// transport. OMDb returns all three ratings in one call.
public struct OMDbClient: Sendable {
    public static let base = URL(string: "https://www.omdbapi.com/")!

    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public func ratings(imdbID: String) async throws -> OMDbRatings {
        var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
        ]
        let response: OMDbResponse = try await http.get(comps.url!)
        guard response.response == "True" else {
            throw OMDbError.notFound(response.error ?? "Not found")
        }
        return OMDbRatings(from: response)
    }
}
