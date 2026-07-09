import Testing
import Foundation
@testable import DebridUI

@Suite struct SkipInputTests {
    @Test func labelUnderMinute() {
        #expect(PlayerModel.SkipFeedback(seconds: 45, id: 0).label == "45s")
    }
    @Test func labelAtMinute() {
        #expect(PlayerModel.SkipFeedback(seconds: 70, id: 0).label == "1:10")
    }
    @Test func labelRoundMinute() {
        #expect(PlayerModel.SkipFeedback(seconds: 120, id: 0).label == "2:00")
    }
    @Test func labelNegativeUsesMagnitude() {
        #expect(PlayerModel.SkipFeedback(seconds: -20, id: 0).label == "20s")
    }
}
