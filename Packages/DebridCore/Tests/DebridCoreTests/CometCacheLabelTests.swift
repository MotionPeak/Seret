import Testing
import Foundation
@testable import DebridCore

@Suite struct CometCacheLabelTests {
    @Test func parsesCachedAndUncachedMarkers() {
        #expect(CometStreamSource.isCachedName("[RD⚡] Comet 2160p") == true)
        #expect(CometStreamSource.isCachedName("[RD⬇️] Comet 1080p") == false)
        #expect(CometStreamSource.isCachedName("Comet 1080p") == false)   // no marker → not cached
        #expect(CometStreamSource.isCachedName(nil) == false)
    }
}
