import Testing
import Foundation
@testable import Seret

/// The pairing server listens on the LAN so a phone can type an OpenSubtitles password for the TV.
/// Anything on the same Wi-Fi can reach it, so its limits are part of its behaviour.
@MainActor
struct LocalPairingServerTests {

    /// The only request it ever serves is a two-field login form. A ceiling well above that, but
    /// far below "unbounded", is what stops a peer that streams bytes without completing a request
    /// from growing the buffer forever while every chunk re-scans the whole accumulation on the
    /// main actor — quadratic work on the thread that draws the UI.
    @Test func theRequestCeilingIsGenerousForAFormAndFarFromUnbounded() {
        #expect(LocalPairingServer.maxRequestBytes >= 4 * 1024)      // a form fits many times over
        #expect(LocalPairingServer.maxRequestBytes <= 128 * 1024)    // …but nothing runs away
        #expect(LocalPairingServer.maxConcurrentConnections >= 1)    // pairing needs one
        #expect(LocalPairingServer.maxConcurrentConnections <= 32)
    }

    /// A password may contain `+` and percent-encoded characters, and form bodies encode a space
    /// as `+` — which `removingPercentEncoding` alone does NOT undo.
    @Test func formFieldsDecodeSpacesAndEncodedCharacters() {
        let fields = LocalPairingServer.formFields("username=a%40b.com&password=p+w%26d%2B1")
        #expect(fields["username"] == "a@b.com")
        #expect(fields["password"] == "p w&d+1")
    }

    /// Malformed bodies must not crash or invent fields.
    @Test func malformedFormBodiesYieldNothingRatherThanGarbage() {
        #expect(LocalPairingServer.formFields("").isEmpty)
        #expect(LocalPairingServer.formFields("novalue").isEmpty)
        #expect(LocalPairingServer.formFields("&&&").isEmpty)
        // An empty value is a real answer (the caller rejects it), not a missing key.
        #expect(LocalPairingServer.formFields("username=&password=") == ["username": "", "password": ""])
    }
}
