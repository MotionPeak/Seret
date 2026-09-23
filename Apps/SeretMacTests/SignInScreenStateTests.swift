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
        #expect(SignInScreenState.make(phase: .failed("Not accepted."), mode: .token).panel == .token(checking: false, error: "Not accepted."))
    }

    @Test func signedInShowsSigningInInEitherMode() {
        #expect(SignInScreenState.make(phase: .signedIn, mode: .code).panel == .preparing("Signing in…"))
        #expect(SignInScreenState.make(phase: .signedIn, mode: .token).panel == .preparing("Signing in…"))
    }
}

private extension RDDeviceCode {
    /// `RDDeviceCode` is Decodable only; the tests build one exactly as Real-Debrid sends it.
    init(fromJSON json: String) {
        self = try! JSONDecoder().decode(RDDeviceCode.self, from: Data(json.utf8))
    }
}
