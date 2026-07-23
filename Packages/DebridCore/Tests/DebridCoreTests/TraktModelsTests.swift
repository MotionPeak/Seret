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
}
