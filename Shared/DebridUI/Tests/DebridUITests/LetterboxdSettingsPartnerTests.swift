import Testing
import Foundation
@testable import DebridUI

@Suite struct LetterboxdSettingsPartnerTests {

    /// The blob on every device predates the partner fields, and a decode failure here is silent
    /// AND destructive: the store falls back to defaults and the username typed on the iPhone goes.
    @Test func aBlobWrittenBeforePartnersExistedKeepsEverything() throws {
        let old = Data(#"{"username":"thebigshin","isEnabled":true,"serverURL":"192.168.1.179:8080"}"#.utf8)
        let decoded = try JSONDecoder().decode(LetterboxdSettings.self, from: old)
        #expect(decoded.username == "thebigshin")
        #expect(decoded.isEnabled)
        #expect(decoded.serverURL == "192.168.1.179:8080")
        #expect(decoded.partnerUsername == "")
        #expect(decoded.partnerName == "")
        #expect(!decoded.hasPartner)
    }

    @Test func partnerFieldsSurviveARoundTrip() throws {
        let settings = LetterboxdSettings(username: "thebigshin", partnerUsername: "nogap",
                                          partnerName: "Noga")
        let decoded = try JSONDecoder().decode(LetterboxdSettings.self,
                                               from: JSONEncoder().encode(settings))
        #expect(decoded.partnerUsername == "nogap")
        #expect(decoded.partnerName == "Noga")
    }

    @Test func theDisplayNameFallsBackToTheUsername() {
        #expect(LetterboxdSettings(partnerUsername: "nogap", partnerName: "Noga").partnerDisplayName == "Noga")
        #expect(LetterboxdSettings(partnerUsername: "nogap", partnerName: "  ").partnerDisplayName == "nogap")
    }

    /// Reading the owner's own list twice would show every film once and crawl Letterboxd twice.
    @Test func onlyADifferentNonEmptyUsernameIsAPartner() {
        #expect(LetterboxdSettings(username: "thebigshin", partnerUsername: "nogap").hasPartner)
        #expect(!LetterboxdSettings(username: "thebigshin", partnerUsername: "").hasPartner)
        #expect(!LetterboxdSettings(username: "thebigshin", partnerUsername: "   ").hasPartner)
        #expect(!LetterboxdSettings(username: "thebigshin", partnerUsername: "TheBigShin ").hasPartner)
    }
}
