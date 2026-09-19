import Testing
import Foundation
@testable import DebridUI

/// The settings blob is stored as JSON in iCloud's key-value store, and the store degrades to
/// defaults when it cannot decode. That makes a decoding failure silent and destructive: the
/// username disappears and the Apple TV goes back to saying "set this on your iPhone".
///
/// So every field added later has to decode leniently.
@Suite struct LetterboxdSettingsDecodingTests {

    @Test func settingsStoredBeforeServerURLExistedStillDecode() throws {
        let legacy = #"{"username":"thebigshin","isEnabled":true}"#
        let settings = try JSONDecoder().decode(LetterboxdSettings.self, from: Data(legacy.utf8))
        #expect(settings.username == "thebigshin")
        #expect(settings.isEnabled)
        #expect(settings.serverURL.isEmpty)
    }

    @Test func aFullBlobRoundTrips() throws {
        let original = LetterboxdSettings(username: "thebigshin", isEnabled: true,
                                          lastImportAt: Date(timeIntervalSince1970: 1_700_000_000),
                                          serverURL: "http://192.168.1.179:8080")
        let back = try JSONDecoder().decode(LetterboxdSettings.self,
                                            from: JSONEncoder().encode(original))
        #expect(back == original)
    }

    /// An empty object is a valid, if useless, blob — not a reason to throw.
    @Test func anEmptyObjectDecodesToDefaults() throws {
        let settings = try JSONDecoder().decode(LetterboxdSettings.self, from: Data("{}".utf8))
        #expect(settings.username.isEmpty)
        #expect(settings.isEnabled == false)
        #expect(settings.serverURL.isEmpty)
    }
}
