#if DEBUG
import Foundation
import Testing
@testable import Seret

@Suite struct VLCSmokePreviewTests {
    @Test func defaultsToApplesPublicStream() {
        #expect(VLCSmokePreview.url(from: ["Seret", "-uiPreview", "vlcsmoke"]) == VLCSmokePreview.defaultURL)
    }

    @Test func aSmokeURLArgumentOverridesIt() {
        let custom = "https://example.com/film.mkv"
        #expect(VLCSmokePreview.url(from: ["Seret", "-smokeURL", custom]) == URL(string: custom))
    }
}
#endif
