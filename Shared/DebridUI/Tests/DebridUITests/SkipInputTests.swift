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
}
