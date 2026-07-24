import Testing
import Foundation
@testable import DebridCore

@Suite struct TraktModelsTests {
    @Test func decodesDeviceCode() throws {
        let json = #"{"device_code":"DC","user_code":"AB12","verification_url":"https://trakt.tv/activate","expires_in":600,"interval":5}"#
        let code = try JSONDecoder().decode(TraktDeviceCode.self, from: Data(json.utf8))
        #expect(code.userCode == "AB12")
        #expect(code.interval == 5)
        #expect(code.verificationURL == "https://trakt.tv/activate")
    }

    @Test func decodesToken() throws {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":7776000,"created_at":1700000000,"token_type":"bearer","scope":"public"}"#
        let token = try JSONDecoder().decode(TraktToken.self, from: Data(json.utf8))
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresIn == 7776000)
    }

    @Test func decodesPlaybackMovie() throws {
        let json = #"""
        [{"progress":35.5,"paused_at":"2026-07-24T10:00:00.000Z","id":1,
          "type":"movie","movie":{"title":"Inception","year":2010,"ids":{"trakt":1,"tmdb":27205}}}]
        """#
        let items = try JSONDecoder().decode([TraktPlaybackItem].self, from: Data(json.utf8))
        #expect(items[0].progress == 35.5)
        #expect(items[0].movie?.ids.tmdb == 27205)
    }

    @Test func decodesPlaybackEpisode() throws {
        let json = #"""
        [{"progress":12.0,"paused_at":"2026-07-24T10:00:00.000Z","id":2,"type":"episode",
          "episode":{"season":2,"number":5,"ids":{"trakt":9,"tmdb":63057}},
          "show":{"title":"GoT","ids":{"trakt":1,"tmdb":1399}}}]
        """#
        let items = try JSONDecoder().decode([TraktPlaybackItem].self, from: Data(json.utf8))
        #expect(items[0].episode?.season == 2)
        #expect(items[0].episode?.number == 5)
        #expect(items[0].show?.ids.tmdb == 1399)
    }

    @Test func decodesWatchedMovies() throws {
        let json = #"[{"plays":3,"movie":{"ids":{"tmdb":27205}}}]"#
        let items = try JSONDecoder().decode([TraktWatchedMovie].self, from: Data(json.utf8))
        #expect(items[0].movie.ids.tmdb == 27205)
    }

    /// Regression: Trakt returned a watched show with NO `seasons` key. `seasons` was non-optional,
    /// so decoding threw — and since refresh() fetches six endpoints together, that one entry wiped
    /// the entire sync (ratings, watched and resume all silently empty). Partial payloads must
    /// degrade to less data, never to no data.
    @Test func decodesWatchedShowMissingSeasons() throws {
        let json = #"[{"plays":3,"show":{"ids":{"tmdb":1399}}}]"#
        let items = try JSONDecoder().decode([TraktWatchedShow].self, from: Data(json.utf8))
        #expect(items[0].show.ids.tmdb == 1399)
        #expect(items[0].seasons == nil)
    }

    @Test func decodesWatchedShowMissingEpisodesAndPlays() throws {
        let json = #"[{"show":{"ids":{"tmdb":1}},"seasons":[{"number":1}]}]"#
        let items = try JSONDecoder().decode([TraktWatchedShow].self, from: Data(json.utf8))
        #expect(items[0].seasons?.first?.episodes == nil)
    }

    @Test func decodesWatchedMovieMissingPlays() throws {
        let json = #"[{"movie":{"ids":{"tmdb":27205}}}]"#
        let items = try JSONDecoder().decode([TraktWatchedMovie].self, from: Data(json.utf8))
        #expect(items[0].movie.ids.tmdb == 27205)
        #expect(items[0].plays == nil)
    }

    @Test func decodesWatchedShows() throws {
        let json = #"""
        [{"show":{"ids":{"tmdb":1399}},
          "seasons":[{"number":2,"episodes":[{"number":5,"plays":1},{"number":6,"plays":2}]}]}]
        """#
        let items = try JSONDecoder().decode([TraktWatchedShow].self, from: Data(json.utf8))
        #expect(items[0].show.ids.tmdb == 1399)
        #expect(items[0].seasons?[0].episodes?.count == 2)
    }
}
