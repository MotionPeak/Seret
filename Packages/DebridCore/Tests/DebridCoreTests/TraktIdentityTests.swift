import Testing
import Foundation
@testable import DebridCore

@Suite struct TraktIdentityTests {
    @Test func movieEncodesTmdbID() throws {
        let ref = TraktMediaRef.movie(tmdb: 27205)
        let json = try ref.scrobbleBodyJSON(progress: 42.5)
        #expect(json.contains("\"tmdb\":27205"))
        #expect(json.contains("\"progress\":42.5"))
        #expect(json.contains("\"movie\""))
    }

    @Test func episodeEncodesShowAndSeasonNumber() throws {
        let ref = TraktMediaRef.episode(showTmdb: 1399, season: 2, number: 5)
        let json = try ref.scrobbleBodyJSON(progress: 10)
        #expect(json.contains("\"show\""))
        #expect(json.contains("\"tmdb\":1399"))
        #expect(json.contains("\"season\":2"))
        #expect(json.contains("\"number\":5"))
    }
}
