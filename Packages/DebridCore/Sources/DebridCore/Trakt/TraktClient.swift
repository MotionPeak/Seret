import Foundation

public enum TraktAuthError: Error, Equatable, Sendable {
    case deviceCodeExpired
    case deniedOrUsed
}

public struct TraktClient: Sendable {
    public static let base = URL(string: "https://api.trakt.tv")!

    let clientID: String
    private let clientSecret: String
    private let http: HTTPClient
    /// Provides the current access token for authed calls; nil for the auth calls themselves.
    private let token: (@Sendable () async throws -> String)?

    public init(clientID: String, clientSecret: String, http: HTTPClient = HTTPClient(),
                token: (@Sendable () async throws -> String)? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.http = http
        self.token = token
    }

    // MARK: Headers

    private var baseHeaders: [String: String] {
        ["Content-Type": "application/json",
         "trakt-api-version": "2",
         "trakt-api-key": clientID]
    }

    func authedHeaders() async throws -> [String: String] {
        var h = baseHeaders
        if let token { h["Authorization"] = "Bearer \(try await token())" }
        return h
    }

    // MARK: Device-code auth

    private struct DeviceCodeRequest: Encodable { let client_id: String }
    private struct PollRequest: Encodable { let code: String; let client_id: String; let client_secret: String }
    private struct RefreshRequest: Encodable {
        let refresh_token: String; let client_id: String; let client_secret: String
        let redirect_uri: String; let grant_type: String
    }

    public func startDeviceCode() async throws -> TraktDeviceCode {
        try await http.post(Self.base.appending(path: "oauth/device/code"),
                            json: DeviceCodeRequest(client_id: clientID), headers: baseHeaders)
    }

    /// One poll attempt: token once authorized, `nil` while pending. Throws on expiry/denial.
    public func pollToken(deviceCode: String) async throws -> TraktToken? {
        do {
            return try await http.post(Self.base.appending(path: "oauth/device/token"),
                                       json: PollRequest(code: deviceCode, client_id: clientID,
                                                         client_secret: clientSecret),
                                       headers: baseHeaders)
        } catch let HTTPError.status(code, _) {
            switch code {
            case 400: return nil                        // authorization_pending
            case 410: throw TraktAuthError.deviceCodeExpired
            case 409, 418: throw TraktAuthError.deniedOrUsed
            case 429: return nil                        // slow down — treated as pending
            default: throw HTTPError.status(code: code, body: "")
            }
        }
    }

    public func awaitToken(
        for code: TraktDeviceCode,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TraktToken {
        var remaining = code.expiresIn
        while remaining > 0 {
            if let token = try await pollToken(deviceCode: code.deviceCode) { return token }
            try await sleep(.seconds(code.interval))
            remaining -= code.interval
        }
        throw TraktAuthError.deviceCodeExpired
    }

    public func refresh(_ token: TraktToken) async throws -> TraktToken {
        try await http.post(Self.base.appending(path: "oauth/token"),
                            json: RefreshRequest(refresh_token: token.refreshToken,
                                                 client_id: clientID, client_secret: clientSecret,
                                                 redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
                                                 grant_type: "refresh_token"),
                            headers: baseHeaders)
    }
}

// MARK: - Scrobble

public enum ScrobbleAction: String, Sendable { case start, pause, stop }

private struct ScrobbleResponse: Decodable { let action: String?; let progress: Double? }

extension TraktClient {
    public func scrobble(_ action: ScrobbleAction, ref: TraktMediaRef, progress: Double) async throws {
        let body = ref.scrobbleBody(progress: progress)
        let _: ScrobbleResponse = try await http.post(
            Self.base.appending(path: "scrobble/\(action.rawValue)"),
            json: body, headers: try await authedHeaders())
    }
}

// MARK: - Sync reads + writes

private struct AckResponse: Decodable {}

extension TraktClient {
    // Reads
    public func playbackMovies() async throws -> [TraktPlaybackItem] {
        try await http.get(Self.base.appending(path: "sync/playback/movies"),
                           headers: try await authedHeaders())
    }
    public func playbackEpisodes() async throws -> [TraktPlaybackItem] {
        try await http.get(Self.base.appending(path: "sync/playback/episodes"),
                           headers: try await authedHeaders())
    }
    public func watchedMovies() async throws -> [TraktWatchedMovie] {
        try await http.get(Self.base.appending(path: "sync/watched/movies"),
                           headers: try await authedHeaders())
    }
    public func watchedShows() async throws -> [TraktWatchedShow] {
        try await http.get(Self.base.appending(path: "sync/watched/shows"),
                           headers: try await authedHeaders())
    }
    public func ratedMovies() async throws -> [TraktRatingItem] {
        try await http.get(Self.base.appending(path: "sync/ratings/movies"),
                           headers: try await authedHeaders())
    }
    public func ratedEpisodes() async throws -> [TraktRatingItem] {
        try await http.get(Self.base.appending(path: "sync/ratings/episodes"),
                           headers: try await authedHeaders())
    }
    public func ratedShows() async throws -> [TraktRatingItem] {
        try await http.get(Self.base.appending(path: "sync/ratings/shows"),
                           headers: try await authedHeaders())
    }

    // Writes
    //
    // Trakt's /sync/{history,ratings} schema: `movies` holds the movie objects FLAT (ids + optional
    // rating), and episodes are addressed by nesting under `shows` → `seasons` → `episodes` (we key
    // episodes by show TMDB id + season/episode number, not an episode id).
    //   {"movies":[{"ids":{"tmdb":1},"rating":9}],
    //    "shows":[{"ids":{"tmdb":2},"seasons":[{"number":1,"episodes":[{"number":3,"rating":9}]}]}]}
    struct SyncBody: Encodable, Equatable {
        struct IDs: Encodable, Equatable { let tmdb: Int }
        struct MovieItem: Encodable, Equatable { let ids: IDs; var rating: Int? }
        struct EpisodeItem: Encodable, Equatable { let number: Int; var rating: Int? }
        struct SeasonItem: Encodable, Equatable { let number: Int; let episodes: [EpisodeItem] }
        /// A show entry is either whole-series (`rating`, no `seasons` — used for a show-level
        /// rating) or a set of episodes addressed by season/number. `nil` fields are omitted.
        struct ShowItem: Encodable, Equatable {
            let ids: IDs
            var rating: Int?
            var seasons: [SeasonItem]?
        }
        var movies: [MovieItem] = []
        var shows: [ShowItem] = []
    }

    /// Group refs into Trakt's body shape, collapsing episodes of the same show/season together so a
    /// batch (e.g. the one-time migration) sends one entry per show rather than one per episode.
    static func groupedBody(_ refs: [TraktMediaRef], rating: Int? = nil) -> SyncBody {
        var body = SyncBody()
        // showTmdb -> season -> episode numbers, preserving first-seen order.
        var showOrder: [Int] = []
        var byShow: [Int: [(season: Int, number: Int)]] = [:]
        for ref in refs {
            switch ref {
            case let .movie(tmdb):
                body.movies.append(.init(ids: .init(tmdb: tmdb), rating: rating))
            case let .show(tmdb):
                // Whole-series entry: rating only, no seasons.
                body.shows.append(.init(ids: .init(tmdb: tmdb), rating: rating, seasons: nil))
            case let .episode(showTmdb, season, number):
                if byShow[showTmdb] == nil { showOrder.append(showTmdb) }
                byShow[showTmdb, default: []].append((season, number))
            }
        }
        for showTmdb in showOrder {
            let eps = byShow[showTmdb] ?? []
            var seasonOrder: [Int] = []
            var bySeason: [Int: [Int]] = [:]
            for ep in eps {
                if bySeason[ep.season] == nil { seasonOrder.append(ep.season) }
                bySeason[ep.season, default: []].append(ep.number)
            }
            let seasons = seasonOrder.map { s in
                SyncBody.SeasonItem(number: s,
                                    episodes: (bySeason[s] ?? []).map { .init(number: $0, rating: rating) })
            }
            body.shows.append(.init(ids: .init(tmdb: showTmdb), rating: nil, seasons: seasons))
        }
        return body
    }

    private func groupedBody(_ refs: [TraktMediaRef], rating: Int? = nil) -> SyncBody {
        Self.groupedBody(refs, rating: rating)
    }

    public func addToHistory(_ refs: [TraktMediaRef]) async throws {
        let _: AckResponse = try await http.post(Self.base.appending(path: "sync/history"),
            json: groupedBody(refs), headers: try await authedHeaders())
    }
    public func removeFromHistory(_ refs: [TraktMediaRef]) async throws {
        let _: AckResponse = try await http.post(Self.base.appending(path: "sync/history/remove"),
            json: groupedBody(refs), headers: try await authedHeaders())
    }
    public func removeFromPlayback(ids: [Int]) async throws {
        struct Body: Encodable { let ids: [Int] }
        let _: AckResponse = try await http.post(Self.base.appending(path: "sync/playback/remove"),
            json: Body(ids: ids), headers: try await authedHeaders())
    }
    public func rate(_ ref: TraktMediaRef, rating: Int) async throws {
        let _: AckResponse = try await http.post(Self.base.appending(path: "sync/ratings"),
            json: groupedBody([ref], rating: rating), headers: try await authedHeaders())
    }
    public func removeRating(_ ref: TraktMediaRef) async throws {
        let _: AckResponse = try await http.post(Self.base.appending(path: "sync/ratings/remove"),
            json: groupedBody([ref]), headers: try await authedHeaders())
    }
}

// MARK: - Public community ratings

extension TraktClient {
    /// Public (api-key-only) community rating for a title, addressed by IMDb id.
    /// Trakt is addressed by Trakt id / slug / IMDb id — never TMDB id — so this joins
    /// on the same IMDb key OMDb already uses.
    ///
    /// Returns `nil` when Trakt has no entry for the id (404) — a normal outcome for
    /// obscure titles, not a failure. Genuine failures (transport, 5xx, malformed body)
    /// still throw so callers can distinguish "no rating" from "lookup broke".
    public func communityRating(imdbID: String, kind: MediaKind) async throws -> TraktCommunityRating? {
        let segment = (kind == .movie) ? "movies" : "shows"
        do {
            return try await http.get(
                Self.base.appending(path: "\(segment)/\(imdbID)/ratings"),
                headers: baseHeaders)
        } catch HTTPError.status(let code, _) where code == 404 {
            return nil
        }
    }
}

// MARK: - Watch history dates

extension TraktClient {
    /// Trakt timestamps sometimes carry fractional seconds and sometimes don't;
    /// try both before giving up.
    private static func parseISO(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// The oldest `watched_at` in the signed-in user's history for a title.
    /// `type` is "movies" or "shows"; `traktID` is the title's numeric Trakt id.
    /// History is newest-first, so the last page's single row is the earliest watch.
    ///
    /// Returns nil when the title has no history, when the dates can't be parsed, or
    /// when Trakt omits the pagination header (we can't identify the oldest row and
    /// won't guess with the newest — an absent header is NOT the same as one page).
    public func firstHistoryDate(type: String, traktID: Int) async throws -> Date? {
        /// `pageCount` is nil when the header is absent or unparseable — "unknown",
        /// deliberately distinct from a genuine count of 1.
        func page(_ n: Int) async throws -> (rows: [TraktHistoryItem], pageCount: Int?) {
            let url = Self.base.appending(path: "sync/history/\(type)/\(traktID)")
                .appending(queryItems: [
                    URLQueryItem(name: "page", value: String(n)),
                    URLQueryItem(name: "limit", value: "1"),
                ])
            let (rows, response): ([TraktHistoryItem], HTTPURLResponse) =
                try await http.getWithHeaders(url, headers: try await authedHeaders())
            let count = response.value(forHTTPHeaderField: "X-Pagination-Page-Count").flatMap(Int.init)
            return (rows, count)
        }
        let first = try await page(1)
        guard !first.rows.isEmpty else { return nil }
        // Unknown page count: page 1 holds the NEWEST watch, so returning it would be a
        // confidently wrong answer. Decline instead.
        guard let pageCount = first.pageCount else { return nil }
        if pageCount <= 1 {
            return first.rows.first.flatMap { Self.parseISO($0.watchedAt) }
        }
        let last = try await page(pageCount)
        return last.rows.first.flatMap { Self.parseISO($0.watchedAt) }
    }
}
