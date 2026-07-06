import Testing
import Foundation
@testable import DebridUI

@Suite struct SkipInputTests {
    @Test func leftThirdIsBack() {
        #expect(RemoteSkipZone.classify(touchX: 10, width: 100) == .back)
    }
    @Test func rightThirdIsForward() {
        #expect(RemoteSkipZone.classify(touchX: 90, width: 100) == .forward)
    }
    @Test func centerIsPlayPause() {
        #expect(RemoteSkipZone.classify(touchX: 50, width: 100) == .playPause)
    }
    @Test func nilTouchIsPlayPause() {
        #expect(RemoteSkipZone.classify(touchX: nil, width: 100) == .playPause)
    }
    @Test func zeroWidthIsPlayPause() {
        #expect(RemoteSkipZone.classify(touchX: 10, width: 0) == .playPause)
    }
    @Test func exactlyAtEdgeFractionIsPlayPause() {
        // 30% boundary is inclusive of center (strict < / >), so exactly 30 is play/pause.
        #expect(RemoteSkipZone.classify(touchX: 30, width: 100) == .playPause)
        #expect(RemoteSkipZone.classify(touchX: 70, width: 100) == .playPause)
    }

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
