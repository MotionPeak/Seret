import Testing
import Foundation
@testable import DebridUI

@Suite struct LetterboxdSettingsTests {
    /// Typed on the iPhone, read on the Apple TV — the same journey the username already makes.
    /// A bare host is what a person types, so it has to mean something.
    @Test func aServerAddressBecomesAUsableURL() {
        #expect(LetterboxdSettings(serverAddress: "192.168.1.179:8080").serverURL?.absoluteString
                == "http://192.168.1.179:8080")
        #expect(LetterboxdSettings(serverAddress: "http://nas.local:8080").serverURL?.absoluteString
                == "http://nas.local:8080")
        #expect(LetterboxdSettings(serverAddress: "  192.168.1.179:8080  ").serverURL?.absoluteString
                == "http://192.168.1.179:8080")
    }

    /// No address means the push is off, not that it points at nothing.
    @Test func anEmptyAddressIsNoServer() {
        #expect(LetterboxdSettings(serverAddress: "").serverURL == nil)
        #expect(LetterboxdSettings(serverAddress: "   ").serverURL == nil)
    }

    @Test func theAddressSurvivesTheRoundTripThroughTheStore() {
        let defaults = UserDefaults(suiteName: "push-settings-\(UUID().uuidString)")!
        let store = UserDefaultsLetterboxdSettingsStore(defaults: defaults)
        store.save(LetterboxdSettings(username: "thebigshin", serverAddress: "nas.local:8080"))
        #expect(store.load().serverAddress == "nas.local:8080")
        #expect(store.load().username == "thebigshin")
    }

    /// 🚨 Settings written before this field existed must still load. A strict decode does not
    /// lose the new field — it loses every field, including the username the import needs.
    @Test func settingsWrittenBeforeTheFieldExistedStillLoad() throws {
        let old = Data(#"{"username":"thebigshin","isEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(LetterboxdSettings.self, from: old)
        #expect(decoded.username == "thebigshin")
        #expect(decoded.isEnabled)
        #expect(decoded.serverAddress.isEmpty)
    }
}
