import Foundation

/// A Trakt content reference, keyed by TMDB ids (the ids Seret already holds).
///
/// `.show` addresses a series as a whole. It is only valid for rating/history-style calls — a show
/// is never scrobbled (playback always scrobbles a concrete `.episode`).
public enum TraktMediaRef: Sendable, Equatable, Hashable {
    case movie(tmdb: Int)
    case show(tmdb: Int)
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
        case let .show(tmdb):
            // Not a real scrobble target — playback always scrobbles a concrete episode. Encoded
            // for totality only; `AppSession.traktRef(for:)` never produces `.show` for playback.
            return ScrobbleBody(show: .init(ids: .init(tmdb: tmdb)), progress: progress)
        case let .episode(showTmdb, season, number):
            return ScrobbleBody(show: .init(ids: .init(tmdb: showTmdb)),
                                episode: .init(season: season, number: number), progress: progress)
        }
    }

    func scrobbleBodyJSON(progress: Double) throws -> String {
        let data = try JSONEncoder().encode(scrobbleBody(progress: progress))
        return String(decoding: data, as: UTF8.self)
    }

}
