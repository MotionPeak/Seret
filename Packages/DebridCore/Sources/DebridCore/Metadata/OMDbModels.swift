import Foundation

/// Derived ratings for a title, mapped from an OMDb response. All optional — OMDb routinely
/// omits Rotten Tomatoes / Metacritic for older or foreign titles.
public struct OMDbRatings: Sendable, Equatable, Codable {
    public let imdb: Double?           // 0.0–10.0
    public let rottenTomatoes: Int?    // 0–100 (percent)
    public let metacritic: Int?        // 0–100

    public init(imdb: Double?, rottenTomatoes: Int?, metacritic: Int?) {
        self.imdb = imdb
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
    }

    /// True when at least one score is present — gates whether the UI shows the ratings row.
    public var hasAny: Bool { imdb != nil || rottenTomatoes != nil || metacritic != nil }
}

public enum OMDbError: Error, Equatable {
    /// OMDb returned `"Response":"False"` (e.g. unknown IMDb id), carrying its `Error` text.
    case notFound(String)
}

/// The OMDb wire response (`?i=tt…`). Capitalized JSON keys mapped to Swift names.
struct OMDbResponse: Decodable {
    let response: String
    let error: String?
    let imdbRating: String?     // "8.7" or "N/A"
    let metascore: String?      // "73" or "N/A"
    let ratings: [Rating]?

    struct Rating: Decodable {
        let source: String      // "Rotten Tomatoes", "Internet Movie Database", "Metacritic"
        let value: String       // "88%", "8.7/10", "73/100"
        enum CodingKeys: String, CodingKey { case source = "Source", value = "Value" }
    }

    enum CodingKeys: String, CodingKey {
        case response = "Response", error = "Error"
        case imdbRating
        case metascore = "Metascore"
        case ratings = "Ratings"
    }
}

extension OMDbRatings {
    /// Map the OMDb wire shape to the derived ratings. IMDb from `imdbRating`, Metacritic from
    /// `Metascore`, Rotten Tomatoes parsed out of the `Ratings` array ("88%"). "N/A" → nil.
    init(from r: OMDbResponse) {
        func double(_ s: String?) -> Double? {
            guard let s, s != "N/A" else { return nil }
            return Double(s)
        }
        func int(_ s: String?) -> Int? {
            guard let s, s != "N/A" else { return nil }
            return Int(s)
        }
        func percent(_ s: String?) -> Int? {
            guard let s else { return nil }
            return Int(s.replacingOccurrences(of: "%", with: ""))
        }
        let rt = r.ratings?.first { $0.source == "Rotten Tomatoes" }?.value
        self.init(imdb: double(r.imdbRating),
                  rottenTomatoes: percent(rt),
                  metacritic: int(r.metascore))
    }
}
