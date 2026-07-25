import Vapor
import DebridCore

/// IMDb / Rotten Tomatoes / Metacritic scores (from OMDb). Absent when no OMDb key is configured
/// or the title has no IMDb id.
struct RatingsDTO: Content, Equatable {
    let imdb: Double?          // 0.0–10.0
    let rottenTomatoes: Int?   // 0–100 (%)
    let metacritic: Int?       // 0–100
}

/// One cast member for the CAST rail.
struct CastDTO: Content, Equatable {
    let name: String
    let character: String?
    let profilePath: String?
}

/// One "More Like This" suggestion. `ownedID` is set when the suggestion is already in the RD
/// library (so the poster links to its detail page); otherwise it renders as a non-clickable poster.
struct SimilarDTO: Content, Equatable {
    let title: String
    let year: Int?
    let posterPath: String?
    let ownedID: String?
}

/// The rich movie detail payload — mirrors the native title page (meta line, ratings, versions,
/// cast, more-like-this). Assembled on demand from TMDB (details + credits + recommendations) and
/// OMDb; every enrichment section degrades gracefully to empty on failure.
struct DetailDTO: Content, Equatable {
    let id: String
    let title: String
    let year: Int?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let runtime: Int?
    let genres: [String]
    let director: String?
    let voteAverage: Double?
    let qualityChips: [String]      // best version's resolution · source · videoCodec · audioCodec
    let bestVersionIndex: Int       // item.sources index the Play button should use
    let versions: [VersionDTO]      // best-first
    let ratings: RatingsDTO?
    let cast: [CastDTO]
    let similar: [SimilarDTO]
}
