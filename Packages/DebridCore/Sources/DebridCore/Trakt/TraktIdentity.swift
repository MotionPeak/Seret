import Foundation

/// A Trakt content reference, keyed by TMDB ids (the ids Seret already holds).
public enum TraktMediaRef: Sendable, Equatable, Hashable {
    case movie(tmdb: Int)
    case episode(showTmdb: Int, season: Int, number: Int)
}

extension TraktMediaRef {
    /// The scrobble request body: identity + `progress` (0–100).
    struct ScrobbleBody: Encodable {
        struct IDs: Encodable { let tmdb: Int }
        struct Item: Encodable { let ids: IDs }
        struct Episode: Encodable { let season: Int; let number: Int }
        var movie: Item?
        var show: Item?
        var episode: Episode?
        let progress: Double
    }

    func scrobbleBody(progress: Double) -> ScrobbleBody {
        switch self {
        case let .movie(tmdb):
            return ScrobbleBody(movie: .init(ids: .init(tmdb: tmdb)), progress: progress)
        case let .episode(showTmdb, season, number):
            return ScrobbleBody(show: .init(ids: .init(tmdb: showTmdb)),
                                episode: .init(season: season, number: number), progress: progress)
        }
    }

    func scrobbleBodyJSON(progress: Double) throws -> String {
        let data = try JSONEncoder().encode(scrobbleBody(progress: progress))
        return String(decoding: data, as: UTF8.self)
    }

    /// The `/sync/history` and `/sync/ratings` item shape (no progress). `rating` optional.
    struct SyncItem: Encodable {
        struct IDs: Encodable { let tmdb: Int }
        struct Item: Encodable { let ids: IDs; var rating: Int? }
        struct Episode: Encodable { let season: Int; let number: Int; var rating: Int? }
        var movie: Item?
        var show: Item?
        var episode: Episode?
    }

    func syncItem(rating: Int? = nil) -> SyncItem {
        switch self {
        case let .movie(tmdb):
            return SyncItem(movie: .init(ids: .init(tmdb: tmdb), rating: rating))
        case let .episode(showTmdb, season, number):
            return SyncItem(show: .init(ids: .init(tmdb: showTmdb), rating: nil),
                            episode: .init(season: season, number: number, rating: rating))
        }
    }
}
