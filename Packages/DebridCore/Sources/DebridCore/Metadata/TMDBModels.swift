import Foundation

/// A row from a TMDB `/search/movie` or `/search/tv` response.
public struct TMDBSearchResult: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let title: String?          // movies
    public let name: String?           // tv
    public let releaseDate: String?    // movies, "YYYY-MM-DD"
    public let firstAirDate: String?   // tv
    public let posterPath: String?
    public let overview: String?
    public let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    public init(id: Int, title: String?, name: String?, releaseDate: String?,
                firstAirDate: String?, posterPath: String?, overview: String?,
                voteAverage: Double?) {
        self.id = id; self.title = title; self.name = name
        self.releaseDate = releaseDate; self.firstAirDate = firstAirDate
        self.posterPath = posterPath; self.overview = overview; self.voteAverage = voteAverage
    }

    /// Movie `title` or TV `name`.
    public var displayTitle: String { title ?? name ?? "" }

    /// Year parsed from the release / first-air date (the leading 4 digits).
    public var year: Int? {
        let date = releaseDate ?? firstAirDate
        guard let prefix = date?.prefix(4) else { return nil }
        return Int(prefix)
    }
}

/// Internal envelope for `/search/*` responses. `internal` (not `private`) so
/// `TMDBClient` — same module, different file — can decode into it.
struct TMDBSearchResponse: Decodable { let results: [TMDBSearchResult] }

public struct TMDBGenre: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// One cast member from TMDB `credits` (movies) or normalized from `aggregate_credits` (shows).
public struct TMDBCastMember: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?
    public let order: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }

    /// `order` defaults so the `/credits` callers (which don't rank) can omit it; the
    /// `append_to_response` path passes it and sorts the rail by it.
    public init(id: Int, name: String, character: String?, profilePath: String?, order: Int? = nil) {
        self.id = id; self.name = name; self.character = character
        self.profilePath = profilePath; self.order = order
    }
}

/// Internal decode shapes for the credits payloads (never exposed on the public model).
struct TMDBMovieCredits: Decodable {
    struct Crew: Decodable {
        let id: Int
        let name: String
        let job: String?
    }
    let cast: [TMDBCastMember]
    let crew: [Crew]
}

struct TMDBAggregateCredits: Decodable {
    struct AggCast: Decodable {
        struct Role: Decodable { let character: String? }
        let id: Int
        let name: String
        let profilePath: String?
        let order: Int?
        let roles: [Role]
        enum CodingKeys: String, CodingKey {
            case id, name, order, roles
            case profilePath = "profile_path"
        }
        var normalized: TMDBCastMember {
            TMDBCastMember(id: id, name: name, character: roles.first?.character,
                           profilePath: profilePath, order: order)
        }
    }
    let cast: [AggCast]
}

struct TMDBCreatedBy: Decodable {
    let id: Int
    let name: String
}

/// The payload behind `similar` on the detail models.
///
/// Sourced from TMDB's `recommendations`, NOT its `similar` endpoint — despite the Swift name.
/// Both return this identical search-shaped body, but `similar` matches on shared keywords and
/// genres and produces poor suggestions (The Prestige → Miss Potter, Jump In!), while
/// `recommendations` is built from what viewers actually watch together and returns the
/// obvious neighbours (Memento, The Illusionist). Verified on-device before switching.
struct TMDBRecommendations: Decodable { let results: [TMDBSearchResult] }

/// A movie's franchise reference, as it appears inline on `/movie/{id}` (`belongs_to_collection`).
/// Present on every entry of a franchise; nil for a standalone film.
public struct TMDBCollectionRef: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let posterPath: String?
    public let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    public init(id: Int, name: String, posterPath: String? = nil, backdropPath: String? = nil) {
        self.id = id; self.name = name
        self.posterPath = posterPath; self.backdropPath = backdropPath
    }
}

/// A full franchise from `/collection/{id}` — the reference plus its member films, unordered as
/// TMDB returns them. `FranchiseOrder` decides the order they are shown in.
public struct TMDBCollection: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let parts: [TMDBSearchResult]

    enum CodingKeys: String, CodingKey {
        case id, name, overview, parts
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    public init(id: Int, name: String, overview: String? = nil, posterPath: String? = nil,
                backdropPath: String? = nil, parts: [TMDBSearchResult] = []) {
        self.id = id; self.name = name; self.overview = overview
        self.posterPath = posterPath; self.backdropPath = backdropPath; self.parts = parts
    }
}

/// One artwork entry from TMDB's `images` block.
///
/// `iso_639_1` is the tell: it is set when the artwork has text burned into it (a language-specific
/// title treatment) and null when the plate is clean. TMDB's default `backdrop_path` is very often
/// a titled one, which is why a hero could render a title twice — once as art inside the image and
/// again as the label drawn over it.
public struct TMDBImageRef: Decodable, Sendable, Equatable {
    public let filePath: String
    /// nil == no burned-in text.
    public let languageCode: String?
    public let voteAverage: Double?
    public let width: Int?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case languageCode = "iso_639_1"
        case voteAverage = "vote_average"
        case width
    }

    public init(filePath: String, languageCode: String?, voteAverage: Double? = nil,
                width: Int? = nil) {
        self.filePath = filePath; self.languageCode = languageCode
        self.voteAverage = voteAverage; self.width = width
    }
}

/// The `images` block appended to a details call.
public struct TMDBImageSet: Decodable, Sendable, Equatable {
    public let backdrops: [TMDBImageRef]
    public let logos: [TMDBImageRef]

    public init(backdrops: [TMDBImageRef], logos: [TMDBImageRef] = []) {
        self.backdrops = backdrops
        self.logos = logos
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backdrops = try c.decodeIfPresent([TMDBImageRef].self, forKey: .backdrops) ?? []
        logos = try c.decodeIfPresent([TMDBImageRef].self, forKey: .logos) ?? []
    }

    enum CodingKeys: String, CodingKey { case backdrops, logos }

    /// The best plate with no burned-in text, or nil when every backdrop is titled.
    ///
    /// Rated first, then widest — TMDB starts most artwork at vote 0, so without the width
    /// tie-break the choice would be arbitrary, and a hero is shown full-bleed on a 4K panel.
    public var textlessBackdropPath: String? {
        backdrops
            .filter { $0.languageCode == nil }
            .max { a, b in
                let (av, bv) = (a.voteAverage ?? 0, b.voteAverage ?? 0)
                return av == bv ? (a.width ?? 0) < (b.width ?? 0) : av < bv
            }?
            .filePath
    }

    /// The title's own artwork: English title treatment first (a logo *is* the title, so an
    /// English one reads correctly even for a foreign-language film), then untagged — never
    /// another language's logo, which would show the wrong alphabet as "the title". Within that,
    /// best-rated, then widest. `.svg` is skipped — ImageIO cannot decode it, so a logo entry
    /// that is only an SVG must lose to a rasterizable one, or fall through to nil.
    public var bestLogoPath: String? {
        let candidates = logos.filter { $0.languageCode == "en" }.isEmpty
            ? logos.filter { $0.languageCode == nil }
            : logos.filter { $0.languageCode == "en" }
        return candidates
            .filter { !$0.filePath.lowercased().hasSuffix(".svg") }
            .max { a, b in
                let (av, bv) = (a.voteAverage ?? 0, b.voteAverage ?? 0)
                return av == bv ? (a.width ?? 0) < (b.width ?? 0) : av < bv
            }?
            .filePath
    }
}

public struct TMDBMovieDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let releaseDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let runtime: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?
    public let originalLanguage: String?   // ISO 639-1
    public let imdbID: String?
    public let cast: [TMDBCastMember]
    /// Every credited director, with their TMDB ids — the ids are what make the credit navigable.
    public let directors: [TMDBPersonRef]
    public let similar: [TMDBSearchResult]

    /// The directors as one printable string, or nil when there are none. Kept so every existing
    /// reader is unaffected by directors gaining ids.
    public var director: String? {
        directors.isEmpty ? nil : directors.map(\.name).joined(separator: ", ")
    }
    /// The franchise this film belongs to, when it belongs to one. Rides along on the details call
    /// we already make, so knowing a film is part of a series costs nothing.
    public let collection: TMDBCollectionRef?
    /// Artwork, when the details call asked for it. Rides along the same way `collection` does.
    public let images: TMDBImageSet?

    /// The backdrop a hero should use: the clean plate when TMDB has one, otherwise whatever
    /// `backdrop_path` gave us. Preferring textless must never mean showing nothing.
    public var preferredBackdropPath: String? {
        images?.textlessBackdropPath ?? backdropPath
    }

    /// The film's own title artwork, when TMDB has one. Rides the same `images` payload as
    /// `preferredBackdropPath` — no extra request.
    public var logoPath: String? { images?.bestLogoPath }

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, credits, images
        case similar = "recommendations"
        case collection = "belongs_to_collection"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case originalLanguage = "original_language"
        case imdbID = "imdb_id"
    }

    public init(id: Int, title: String, releaseDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, runtime: Int?,
                genres: [TMDBGenre], voteAverage: Double?,
                originalLanguage: String? = nil, imdbID: String? = nil,
                cast: [TMDBCastMember] = [], directors: [TMDBPersonRef] = [],
                similar: [TMDBSearchResult] = [], collection: TMDBCollectionRef? = nil,
                images: TMDBImageSet? = nil) {
        self.id = id; self.title = title; self.releaseDate = releaseDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.runtime = runtime; self.genres = genres; self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage; self.imdbID = imdbID
        self.cast = cast; self.directors = directors; self.similar = similar
        self.collection = collection; self.images = images
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        runtime = try c.decodeIfPresent(Int.self, forKey: .runtime)
        genres = try c.decodeIfPresent([TMDBGenre].self, forKey: .genres) ?? []
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        originalLanguage = try c.decodeIfPresent(String.self, forKey: .originalLanguage)
        imdbID = try c.decodeIfPresent(String.self, forKey: .imdbID)
        let credits = try c.decodeIfPresent(TMDBMovieCredits.self, forKey: .credits)
        // Deduped by person id BEFORE the cap, for the same reason `directors` is: TMDB lists a
        // person once per role, so an actor playing two parts arrived twice. `TMDBCastMember`'s id
        // IS the person id and the Cast rail is a plain `ForEach(cast)`, so a duplicate meant
        // duplicate SwiftUI identities — which on tvOS leaves stale, unfocusable cells behind.
        var seenCast = Set<Int>()
        cast = (credits?.cast ?? []).sorted { ($0.order ?? .max) < ($1.order ?? .max) }
                                    .filter { seenCast.insert($0.id).inserted }
                                    .prefix(10).map { $0 }
        // Deduped by person id, not by name: a co-director credited under two jobs would otherwise
        // be listed twice, and two different people can share a name.
        var seenDirectors = Set<Int>()
        directors = (credits?.crew ?? [])
            .filter { $0.job == "Director" }
            .filter { seenDirectors.insert($0.id).inserted }
            .map { TMDBPersonRef(id: $0.id, name: $0.name) }
        similar = (try c.decodeIfPresent(TMDBRecommendations.self, forKey: .similar)?.results ?? [])
        collection = try c.decodeIfPresent(TMDBCollectionRef.self, forKey: .collection)
        images = try c.decodeIfPresent(TMDBImageSet.self, forKey: .images)
    }
}

/// Cast + crew for a title (`/movie|tv/{id}/credits`). Powers the CAST rail and the director credit.
public struct TMDBCredits: Decodable, Sendable, Equatable {
    public let cast: [TMDBCastMember]
    public let crew: [TMDBCrewMember]

    /// The credited director — the first crew member whose job is "Director", if any.
    public var director: String? { crew.first { $0.job == "Director" }?.name }

    public init(cast: [TMDBCastMember], crew: [TMDBCrewMember]) {
        self.cast = cast; self.crew = crew
    }
}

public struct TMDBCrewMember: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let job: String?
    public let department: String?

    enum CodingKeys: String, CodingKey { case id, name, job, department }

    public init(id: Int, name: String, job: String?, department: String? = nil) {
        self.id = id; self.name = name; self.job = job; self.department = department
    }
}

public struct TMDBTVDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let firstAirDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let numberOfSeasons: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?
    public let originalLanguage: String?   // ISO 639-1
    public let imdbID: String?             // from append_to_response=external_ids
    public let cast: [TMDBCastMember]
    /// Every credited creator, with their TMDB ids — a show's equivalent of a movie's director.
    public let creatorRefs: [TMDBPersonRef]
    public let similar: [TMDBSearchResult]

    /// The creators' names. Kept so every existing reader is unaffected by creators gaining ids.
    public var creators: [String] { creatorRefs.map(\.name) }

    /// Artwork, when the details call asked for it.
    public let images: TMDBImageSet?

    /// The backdrop a hero should use: the clean plate when TMDB has one, otherwise whatever
    /// `backdrop_path` gave us. Preferring textless must never mean showing nothing.
    public var preferredBackdropPath: String? {
        images?.textlessBackdropPath ?? backdropPath
    }

    /// The show's own title artwork, when TMDB has one. Rides the same `images` payload as
    /// `preferredBackdropPath` — no extra request.
    public var logoPath: String? { images?.bestLogoPath }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, images
        case similar = "recommendations"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case voteAverage = "vote_average"
        case originalLanguage = "original_language"
        case externalIDs = "external_ids"
        case aggregateCredits = "aggregate_credits"
        case createdBy = "created_by"
    }

    private struct ExternalIDs: Decodable { let imdb_id: String? }

    public init(id: Int, name: String, firstAirDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, numberOfSeasons: Int?,
                genres: [TMDBGenre], voteAverage: Double?,
                originalLanguage: String? = nil, imdbID: String? = nil,
                cast: [TMDBCastMember] = [], creatorRefs: [TMDBPersonRef] = [],
                similar: [TMDBSearchResult] = [], images: TMDBImageSet? = nil) {
        self.id = id; self.name = name; self.firstAirDate = firstAirDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.numberOfSeasons = numberOfSeasons; self.genres = genres; self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage; self.imdbID = imdbID
        self.cast = cast; self.creatorRefs = creatorRefs; self.similar = similar
        self.images = images
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        numberOfSeasons = try c.decodeIfPresent(Int.self, forKey: .numberOfSeasons)
        genres = try c.decodeIfPresent([TMDBGenre].self, forKey: .genres) ?? []
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        originalLanguage = try c.decodeIfPresent(String.self, forKey: .originalLanguage)
        imdbID = try c.decodeIfPresent(ExternalIDs.self, forKey: .externalIDs)?.imdb_id
        images = try c.decodeIfPresent(TMDBImageSet.self, forKey: .images)
        let agg = try c.decodeIfPresent(TMDBAggregateCredits.self, forKey: .aggregateCredits)
        // Deduped by person id before the cap — see the movie initializer above.
        var seenCast = Set<Int>()
        cast = (agg?.cast ?? []).sorted { ($0.order ?? .max) < ($1.order ?? .max) }
                                .filter { seenCast.insert($0.id).inserted }
                                .prefix(10).map { $0.normalized }
        creatorRefs = (try c.decodeIfPresent([TMDBCreatedBy].self, forKey: .createdBy) ?? [])
            .map { TMDBPersonRef(id: $0.id, name: $0.name) }
        similar = (try c.decodeIfPresent(TMDBRecommendations.self, forKey: .similar)?.results ?? [])
    }
}

/// One episode from a TMDB `/tv/{id}/season/{n}` response.
public struct TMDBEpisodeDetails: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let episodeNumber: Int
    public let name: String?
    public let overview: String?
    public let stillPath: String?
    public let runtime: Int?
    public let airDate: String?

    public var id: Int { episodeNumber }

    enum CodingKeys: String, CodingKey {
        case name, overview, runtime
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }

    public init(episodeNumber: Int, name: String?, overview: String?,
                stillPath: String?, runtime: Int?, airDate: String?) {
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.runtime = runtime
        self.airDate = airDate
    }
}

/// A TMDB `/tv/{id}/season/{n}` response — the episodes for one season.
public struct TMDBSeasonDetails: Decodable, Sendable, Equatable {
    public let seasonNumber: Int
    public let episodes: [TMDBEpisodeDetails]

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodes
    }

    public init(seasonNumber: Int, episodes: [TMDBEpisodeDetails]) {
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}

/// A trailer/teaser entry from `/movie/{id}/videos` or `/tv/{id}/videos`.
public struct TMDBVideo: Decodable, Sendable, Equatable {
    public let key: String        // YouTube video id
    public let site: String       // e.g. "YouTube"
    public let type: String       // e.g. "Trailer" / "Teaser"
    public let name: String?

    public init(key: String, site: String, type: String, name: String? = nil) {
        self.key = key; self.site = site; self.type = type; self.name = name
    }
}

public extension Array where Element == TMDBVideo {
    /// The first YouTube Trailer, else the first YouTube Teaser, else nil.
    var firstYouTubeTrailer: TMDBVideo? {
        let youTube = filter { $0.site == "YouTube" }
        return youTube.first { $0.type == "Trailer" } ?? youTube.first { $0.type == "Teaser" }
    }
}

/// Envelope for `/videos` responses.
struct TMDBVideosResponse: Decodable { let results: [TMDBVideo] }
