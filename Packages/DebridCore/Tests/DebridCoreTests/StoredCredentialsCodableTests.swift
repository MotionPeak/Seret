import Testing
import Foundation
@testable import DebridCore

@Suite struct StoredCredentialsCodableTests {
    @Test func decodesLegacyJSONWithoutIsStaticAsFalse() throws {
        // Credentials persisted before the isStatic field existed must still load.
        let json = #"""
        {"token":{"access_token":"AT","refresh_token":"RT","expires_in":3600,"token_type":"Bearer"},
         "deviceCredentials":{"client_id":"CID","client_secret":"CS"},
         "obtainedAt":700000000}
        """#
        let creds = try JSONDecoder().decode(StoredCredentials.self, from: Data(json.utf8))
        #expect(creds.isStatic == false)
        #expect(creds.token.accessToken == "AT")
    }

    @Test func roundTripsIsStaticTrue() throws {
        let original = StoredCredentials(
            token: RDToken(accessToken: "AT", refreshToken: "", expiresIn: 0, tokenType: "Bearer"),
            deviceCredentials: RDDeviceCredentials(clientID: "", clientSecret: ""),
            obtainedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
            isStatic: true)
        let decoded = try JSONDecoder().decode(StoredCredentials.self,
                                               from: try JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.isStatic == true)
    }
}
