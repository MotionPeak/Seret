import Foundation
import Testing
@testable import Seret

@MainActor
@Suite struct DisplaySleepGuardTests {
    private final class Spy: NSObject {}

    @Test func beginsOnceWhilePlaying() {
        var beginCount = 0
        let guardObject = DisplaySleepGuard(begin: { beginCount += 1; return Spy() }, end: { _ in })
        guardObject.update(isPlaying: true)
        guardObject.update(isPlaying: true)
        guardObject.update(isPlaying: true)
        #expect(beginCount == 1)
    }

    @Test func pausingEndsIt() {
        var beginCount = 0, endCount = 0
        let guardObject = DisplaySleepGuard(begin: { beginCount += 1; return Spy() },
                                            end: { _ in endCount += 1 })
        guardObject.update(isPlaying: true)
        guardObject.update(isPlaying: false)
        #expect(beginCount == 1)
        #expect(endCount == 1)
    }

    @Test func releaseIsIdempotent() {
        var endCount = 0
        let guardObject = DisplaySleepGuard(begin: { Spy() }, end: { _ in endCount += 1 })
        guardObject.update(isPlaying: true)
        guardObject.release()
        guardObject.release()
        #expect(endCount == 1)
    }

    @Test func neverEndsWhatItNeverBegan() {
        var endCount = 0
        let guardObject = DisplaySleepGuard(begin: { Spy() }, end: { _ in endCount += 1 })
        guardObject.release()
        #expect(endCount == 0)
    }
}
