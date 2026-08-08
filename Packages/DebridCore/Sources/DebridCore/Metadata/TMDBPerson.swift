import Foundation

/// A person you can navigate to: just enough to identify them and label the control that opens
/// them. Deliberately tiny — it is carried as a SwiftUI navigation value, so it must be `Hashable`
/// and cheap to compare.
///
/// The full person (photo, filmography) is fetched by `TMDBClient.person(id:)` on arrival, not
/// carried along the way.
public struct TMDBPersonRef: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// One entry in a person's filmography, from `/person/{id}/combined_credits`.
///
/// A credit is a search result plus a role, so it *wraps* `TMDBSearchResult` and decodes it from
/// the same JSON object rather than restating title / poster / date. That is what makes the trip to
/// a `SearchHit` a one-liner in the UI layer, and what lets a credit render through the exact same
/// poster tile a search result does.
public struct TMDBPersonCredit: Sendable, Hashable, Identifiable {
    public let result: TMDBSearchResult
    public let kind: MediaKind
    /// Acting credits only — the role played. `nil` on crew credits.
    public let character: String?
    /// Crew credits only — e.g. "Director". `nil` on cast credits.
    public let job: String?
    public let popularity: Double?

    /// Unique per title *and* kind: TMDB numbers movies and shows separately, so a movie 42 and a
    /// show 42 are different titles.
    public var id: String { "\(kind.rawValue)-\(result.id)" }

    public init(result: TMDBSearchResult, kind: MediaKind, character: String? = nil,
                job: String? = nil, popularity: Double? = nil) {
        self.result = result
        self.kind = kind
        self.character = character
        self.job = job
        self.popularity = popularity
    }
}

extension TMDBPersonCredit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case character, job, popularity
        case mediaType = "media_type"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .mediaType) {
        case "movie": kind = .movie
        case "tv": kind = .show
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .mediaType, in: c,
                debugDescription: "credit is neither a movie nor a show")
        }
        // The same JSON object, read again through the search-result shape.
        result = try TMDBSearchResult(from: decoder)
        character = try c.decodeIfPresent(String.self, forKey: .character)
        job = try c.decodeIfPresent(String.self, forKey: .job)
        popularity = try c.decodeIfPresent(Double.self, forKey: .popularity)
    }
}

/// Decodes an array of credits **element by element, dropping the ones that fail**.
///
/// `combined_credits` can carry media types we do not model. Decoding straight into
/// `[TMDBPersonCredit]` would throw on the first of them and lose the entire filmography, so each
/// element is decoded through a wrapper whose init never throws.
///
/// The wrapper — rather than a `try?` inside an unkeyed-container loop — is deliberate: a throwing
/// `decode` does not reliably advance `currentIndex`, which loops forever.
struct LossyCredits: Decodable {
    let values: [TMDBPersonCredit]

    private struct Element: Decodable {
        let value: TMDBPersonCredit?
        init(from decoder: any Decoder) throws {
            value = try? TMDBPersonCredit(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        values = try [Element](from: decoder).compactMap(\.value)
    }
}

/// A person and their whole filmography, from `/person/{id}?append_to_response=combined_credits`.
///
/// Deliberately thin on biography: the app shows what someone has been in so you can play it, not
/// who they are. Name, photo and department are all the header needs.
public struct TMDBPersonDetails: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    /// TMDB's own guess at what they are primarily known for — "Acting", "Directing", …
    public let knownForDepartment: String?
    /// Everything they appeared in. Unfiltered — ranking is the caller's job.
    public let castCredits: [TMDBPersonCredit]
    /// Everything they worked on behind the camera, every department. Unfiltered.
    public let crewCredits: [TMDBPersonCredit]

    private enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case combinedCredits = "combined_credits"
    }

    private struct CombinedCredits: Decodable {
        let cast: LossyCredits?
        let crew: LossyCredits?
    }

    public init(id: Int, name: String, profilePath: String? = nil,
                knownForDepartment: String? = nil,
                castCredits: [TMDBPersonCredit] = [], crewCredits: [TMDBPersonCredit] = []) {
        self.id = id
        self.name = name
        self.profilePath = profilePath
        self.knownForDepartment = knownForDepartment
        self.castCredits = castCredits
        self.crewCredits = crewCredits
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        profilePath = try c.decodeIfPresent(String.self, forKey: .profilePath)
        knownForDepartment = try c.decodeIfPresent(String.self, forKey: .knownForDepartment)
        let combined = try c.decodeIfPresent(CombinedCredits.self, forKey: .combinedCredits)
        castCredits = combined?.cast?.values ?? []
        crewCredits = combined?.crew?.values ?? []
    }
}
