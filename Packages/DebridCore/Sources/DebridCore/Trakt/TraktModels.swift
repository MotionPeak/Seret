import Foundation

public struct TraktDeviceCode: Decodable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: String
    public let expiresIn: Int
    public let interval: Int

    public init(deviceCode: String, userCode: String, verificationURL: String,
                expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TraktToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let createdAt: Int
    public let tokenType: String
    public let scope: String

    public init(accessToken: String, refreshToken: String, expiresIn: Int,
                createdAt: Int, tokenType: String, scope: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.createdAt = createdAt
        self.tokenType = tokenType
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
        case tokenType = "token_type"
        case scope
    }
}

// MARK: - Sync DTOs (playback / watched / ratings)

public struct TraktIDs: Decodable, Sendable, Equatable {
    public let tmdb: Int?
    public let trakt: Int?
    public init(tmdb: Int?, trakt: Int?) { self.tmdb = tmdb; self.trakt = trakt }
}

public struct TraktMovieRef: Decodable, Sendable, Equatable {
    public let ids: TraktIDs
    public init(ids: TraktIDs) { self.ids = ids }
}

public struct TraktShowRef: Decodable, Sendable, Equatable {
    public let ids: TraktIDs
    public init(ids: TraktIDs) { self.ids = ids }
}

public struct TraktEpisodeRef: Decodable, Sendable, Equatable {
    public let season: Int
    public let number: Int
    public let ids: TraktIDs
    public init(season: Int, number: Int, ids: TraktIDs) {
        self.season = season; self.number = number; self.ids = ids
    }
}

/// One paused item from `/sync/playback/{movies,episodes}`.
public struct TraktPlaybackItem: Decodable, Sendable, Equatable {
    public let progress: Double
    public let pausedAt: String
    public let type: String
    public let movie: TraktMovieRef?
    public let show: TraktShowRef?
    public let episode: TraktEpisodeRef?

    public init(progress: Double, pausedAt: String, type: String,
                movie: TraktMovieRef?, show: TraktShowRef?, episode: TraktEpisodeRef?) {
        self.progress = progress; self.pausedAt = pausedAt; self.type = type
        self.movie = movie; self.show = show; self.episode = episode
    }

    enum CodingKeys: String, CodingKey {
        case progress, type, movie, show, episode
        case pausedAt = "paused_at"
    }
}

public struct TraktWatchedMovie: Decodable, Sendable, Equatable {
    public let plays: Int
    public let movie: TraktMovieRef
    public init(plays: Int, movie: TraktMovieRef) { self.plays = plays; self.movie = movie }
}

/// `/sync/watched/shows` collapses to the set of (showTmdb, season, number) watched.
public struct TraktWatchedShow: Decodable, Sendable, Equatable {
    public struct Season: Decodable, Sendable, Equatable {
        public struct Ep: Decodable, Sendable, Equatable { public let number: Int; public let plays: Int }
        public let number: Int
        public let episodes: [Ep]
    }
    public let show: TraktShowRef
    public let seasons: [Season]
}

public struct TraktRatingItem: Decodable, Sendable, Equatable {
    public let rating: Int
    public let type: String
    public let movie: TraktMovieRef?
    public let show: TraktShowRef?
    public let episode: TraktEpisodeRef?

    public init(rating: Int, type: String, movie: TraktMovieRef?,
                show: TraktShowRef?, episode: TraktEpisodeRef?) {
        self.rating = rating; self.type = type
        self.movie = movie; self.show = show; self.episode = episode
    }
}
