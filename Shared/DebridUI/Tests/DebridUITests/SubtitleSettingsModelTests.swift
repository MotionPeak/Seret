import Testing
import Foundation
@testable import DebridUI

@MainActor
@Suite struct SubtitleSettingsModelTests {
    @Test func defaultsToMediumSystemWhite() {
        let m = SubtitleSettingsModel(defaults: UserDefaults(suiteName: "t.\(UUID())")!)
        #expect(m.preferences == .default)
        #expect(m.preferences.size == .medium)
        #expect(m.preferences.size.scale == 1.0)
    }

    @Test func sizeScalesAreOrdered() {
        #expect(SubtitlePreferences.Size.small.scale < SubtitlePreferences.Size.medium.scale)
        #expect(SubtitlePreferences.Size.large.scale < SubtitlePreferences.Size.extraLarge.scale)
    }

    @Test func persistsAcrossInstances() {
        let suite = "t.\(UUID())"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let m = SubtitleSettingsModel(defaults: d)
        m.preferences.size = .large
        m.preferences.font = .serif
        m.preferences.color = .yellow
        // A fresh model over the same store reloads the saved choices.
        let reloaded = SubtitleSettingsModel(defaults: d)
        #expect(reloaded.preferences.size == .large)
        #expect(reloaded.preferences.font == .serif)
        #expect(reloaded.preferences.color == .yellow)
    }
}
