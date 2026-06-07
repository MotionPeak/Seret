import Testing
import Foundation
@testable import DebridUI

@MainActor
@Suite struct TrailerSettingsModelTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "trailer-test-\(UUID().uuidString)")!
    }

    @Test func defaultsToOn() {
        let m = TrailerSettingsModel(defaults: freshDefaults())
        #expect(m.autoplayTrailers == true)
    }

    @Test func persistsAcrossInstances() {
        let d = freshDefaults()
        let m1 = TrailerSettingsModel(defaults: d)
        m1.autoplayTrailers = false
        let m2 = TrailerSettingsModel(defaults: d)   // re-read from the same defaults
        #expect(m2.autoplayTrailers == false)
    }
}
