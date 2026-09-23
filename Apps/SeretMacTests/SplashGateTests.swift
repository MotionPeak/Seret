import DebridUI
import Foundation
import Testing
@testable import Seret

@Suite struct SplashGateTests {
    @Test func neverBeforeTheAnimationEnds() {
        #expect(!SplashGate.shouldHide(animationFinished: false, session: .signedOut,
                                       library: nil, heldFor: .seconds(999)))
        #expect(!SplashGate.shouldHide(animationFinished: false, session: .signedIn,
                                       library: .loaded, heldFor: .seconds(999)))
    }

    @Test func signedOutGoesAsSoonAsTheAnimationEnds() {
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedOut,
                                      library: nil, heldFor: .zero))
    }

    @Test func holdsWhileTheFirstLoadRuns() {
        #expect(!SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                       library: .loading, heldFor: .seconds(1)))
    }

    @Test func anyAnswerFromTheLibraryReleasesIt() {
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                      library: .loaded, heldFor: .seconds(1)))
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                      library: .empty, heldFor: .seconds(1)))
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                      library: .failed("x"), heldFor: .seconds(1)))
    }

    @Test func neverHoldsPastTheCap() {
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                      library: .loading, heldFor: .seconds(6)))
    }

    @Test func noStoreYetHoldsUntilTheCap() {
        #expect(!SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                       library: nil, heldFor: .seconds(1)))
        #expect(SplashGate.shouldHide(animationFinished: true, session: .signedIn,
                                      library: nil, heldFor: .seconds(6)))
    }
}
