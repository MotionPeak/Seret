import DebridCore
import DebridUI
import Foundation
import Testing
@testable import Seret

@Suite struct SignInScreenStateTests {
    private let code = RDDeviceCode(fromJSON: """
        {"device_code":"DC","user_code":"W6XD2P7N","interval":5,"expires_in":600,"verification_url":"https://real-debrid.com/device"}
        """)

    @Test func aCodeIsShownInTwoGroupsOfFour() {
        #expect(SignInScreenState.formatUserCode("W6XD2P7N") == "W6XD 2P7N")
        #expect(SignInScreenState.formatUserCode("ABCDEF") == "ABCD EF")
        #expect(SignInScreenState.formatUserCode("AB-CD") == "AB-CD")        // not plain: left alone
    }

    @Test func theCountdownReadsMinutesAndSeconds() {
        #expect(SignInScreenState.countdown(secondsLeft: 598) == "9:58")
        #expect(SignInScreenState.countdown(secondsLeft: 61) == "1:01")
        #expect(SignInScreenState.countdown(secondsLeft: -3) == "0:00")
    }

    @Test func codeModeWalksThroughPreparingTheCodeAndFailure() {
        #expect(SignInScreenState.make(phase: .requestingCode, mode: .code).panel == .preparing("Preparing sign-in…"))
        #expect(SignInScreenState.make(phase: .awaitingAuthorization(code), mode: .code).panel
                == .code(userCode: "W6XD2P7N", verificationURL: URL(string: "https://real-debrid.com/device"), expiresIn: 600))
        #expect(SignInScreenState.make(phase: .failed("Real-Debrid is busy."), mode: .code).panel == .failed("Real-Debrid is busy."))
    }

    @Test func tokenModeKeepsTheFieldAndShowsProgressOrTheErrorInline() {
        #expect(SignInScreenState.make(phase: .awaitingAuthorization(code), mode: .token).panel == .token(checking: false, error: nil))
        #expect(SignInScreenState.make(phase: .validatingToken, mode: .token).panel == .token(checking: true, error: nil))
        #expect(SignInScreenState.make(phase: .failed("Not accepted."), mode: .token, tokenSubmitted: true).panel
                == .token(checking: false, error: "Not accepted."))
    }

    /// "Busy" is the error that offers *Use a Token*; it must not greet the viewer there as a token error.
    @Test func aCodeRouteFailureIsNotShownAsATokenError() {
        #expect(SignInScreenState.make(phase: .failed("Real-Debrid is busy."), mode: .token).panel
                == .token(checking: false, error: nil))
        #expect(SignInScreenState.make(phase: .failed("Real-Debrid is busy."), mode: .code, tokenSubmitted: true).panel
                == .failed("Real-Debrid is busy."))
    }

    @Test func theCodeClockRestartsOnlyForANewCode() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var clock = SignInScreenState.CodeClock()
        clock.show("W6XD2P7N", at: start)
        #expect(clock.secondsLeft(expiresIn: 600, at: start.addingTimeInterval(90)) == 510)
        clock.show("W6XD2P7N", at: start.addingTimeInterval(90))   // Try Again reused it / panel reappeared
        #expect(clock.secondsLeft(expiresIn: 600, at: start.addingTimeInterval(90)) == 510)
        clock.show("NEWCODE1", at: start.addingTimeInterval(700))
        #expect(clock.secondsLeft(expiresIn: 600, at: start.addingTimeInterval(700)) == 600)
    }

    @Test func signedInShowsSigningInInEitherMode() {
        #expect(SignInScreenState.make(phase: .signedIn, mode: .code).panel == .preparing("Signing in…"))
        #expect(SignInScreenState.make(phase: .signedIn, mode: .token).panel == .preparing("Signing in…"))
    }

    // MARK: - TorBox

    private let torBoxCode = RDDeviceCode(fromJSON: """
        {"device_code":"TBD","user_code":"AB12CD","interval":5,"expires_in":600,"verification_url":"tor.box/link"}
        """)

    @Test func theStateCarriesItsProviderAndDefaultsToRealDebrid() {
        #expect(SignInScreenState.make(phase: .requestingCode, mode: .code).provider == .realDebrid)
        #expect(SignInScreenState.make(phase: .requestingCode, mode: .code, provider: .torBox).provider == .torBox)
        #expect(SignInScreenState.make(phase: .signedIn, mode: .token, provider: .torBox).provider == .torBox)
    }

    /// A different provider is a different sign-in: nothing typed for one may carry over to the
    /// other — least of all a pasted key — and the card starts again on the code.
    @Test func providerSwitchResetsState() {
        var entry = SignInScreenState.Entry(provider: .realDebrid)
        entry.mode = .token
        entry.token = "PASTED-RD-TOKEN"
        entry.tokenSubmitted = true
        entry.switchProvider(to: .torBox)
        #expect(entry == SignInScreenState.Entry(provider: .torBox))
        #expect(entry.mode == .code)
        #expect(entry.token.isEmpty)
        #expect(entry.tokenSubmitted == false)
    }

    @Test func aSubmitHandsOverTheTokenOnceAndMarksItSubmitted() {
        var entry = SignInScreenState.Entry(provider: .torBox)
        entry.mode = .token
        #expect(entry.submit(phase: .idle) == nil)                    // nothing typed
        entry.token = "   "
        #expect(entry.submit(phase: .idle) == nil)                    // only whitespace
        #expect(entry.tokenSubmitted == false)
        entry.token = "tb-key"
        #expect(entry.submit(phase: .validatingToken) == nil)         // Return while checking: no second check
        #expect(entry.tokenSubmitted == false)
        #expect(entry.submit(phase: .failed("x")) == "tb-key")
        #expect(entry.tokenSubmitted)
    }

    @Test func checkingAKeyIsWordedForTheProvider() {
        #expect(SignInScreenState.make(phase: .validatingToken, mode: .code).panel == .preparing("Checking token…"))
        #expect(SignInScreenState.make(phase: .validatingToken, mode: .code, provider: .torBox).panel
                == .preparing("Checking key…"))
    }

    /// TorBox hands back a friendly address with no scheme; the browser needs one.
    @Test func aSchemeLessVerificationAddressGetsHTTPS() {
        #expect(SignInScreenState.verificationURL("tor.box/link") == URL(string: "https://tor.box/link"))
        #expect(SignInScreenState.verificationURL(" https://real-debrid.com/device ")
                == URL(string: "https://real-debrid.com/device"))
        #expect(SignInScreenState.verificationURL("") == nil)
        #expect(SignInScreenState.verificationURL("ftp://tor.box/link") == nil)
        #expect(SignInScreenState.make(phase: .awaitingAuthorization(torBoxCode), mode: .code, provider: .torBox).panel
                == .code(userCode: "AB12CD", verificationURL: URL(string: "https://tor.box/link"), expiresIn: 600))
    }

    @Test func theCodePageIsRealDebridsFixedAddressOrTorBoxsOwn() {
        let rd = SignInScreenState.Copy(provider: .realDebrid)
        let tb = SignInScreenState.Copy(provider: .torBox)
        #expect(rd.codePage(for: URL(string: "https://real-debrid.com/device?x=1")) == "real-debrid.com/device")
        #expect(rd.codePage(for: nil) == "real-debrid.com/device")
        #expect(tb.codePage(for: URL(string: "https://tor.box/link")) == "tor.box/link")
        #expect(tb.codePage(for: URL(string: "https://torbox.app/")) == "torbox.app")
        #expect(tb.codePage(for: nil) == "torbox.app")
    }

    @Test func realDebridCopyIsUnchanged() {
        let copy = SignInScreenState.Copy(provider: .realDebrid)
        #expect(copy.tokenMode == "Use a token")
        #expect(copy.tokenFailureAction == "Use a Token")
        #expect(copy.tokenPlaceholder == "Paste your Real-Debrid API token")
        #expect(copy.tokenPage == "real-debrid.com/apitoken")
        #expect(copy.tokenPageURL == URL(string: "https://real-debrid.com/apitoken"))
    }

    @Test func torBoxCopyNamesTorBox() {
        let copy = SignInScreenState.Copy(provider: .torBox)
        #expect(copy.tokenMode == "Use an API key")
        #expect(copy.tokenFailureAction == "Use an API Key")
        #expect(copy.tokenPlaceholder == "Paste your TorBox API key")
        #expect(copy.tokenPage == "torbox.app/settings")
        #expect(copy.tokenPageURL == URL(string: "https://torbox.app/settings"))
        #expect(SignInScreenState.make(phase: .idle, mode: .code, provider: .torBox).copy == copy)
    }
}

private extension RDDeviceCode {
    /// `RDDeviceCode` is Decodable only; the tests build one exactly as Real-Debrid sends it.
    init(fromJSON json: String) {
        self = try! JSONDecoder().decode(RDDeviceCode.self, from: Data(json.utf8))
    }
}
