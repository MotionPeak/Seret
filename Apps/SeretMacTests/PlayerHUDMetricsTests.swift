import Testing
@testable import Seret

@Suite struct PlayerHUDMetricsTests {
    @Test func thePanelNeverGrowsPastItsCap() {
        #expect(PlayerHUDMetrics.panelWidth(windowWidth: 1000) == 912)
        #expect(PlayerHUDMetrics.panelWidth(windowWidth: 3000) == 912)
        #expect(PlayerHUDMetrics.panelWidth(windowWidth: 5120) == 912)
    }

    @Test func aNarrowWindowKeepsTheMargins() {
        #expect(PlayerHUDMetrics.panelWidth(windowWidth: 800) == 752)
    }

    /// Structural: the HUD is sized in points and never scales with the window, so these constants
    /// must stay fixed.
    @Test func theControlsAreFixedSizes() {
        #expect(PlayerHUDMetrics.icon == 18)
        #expect(PlayerHUDMetrics.iconButton == 35)
        #expect(PlayerHUDMetrics.playButton == 50)
        #expect(PlayerHUDMetrics.playIcon == 27)
    }
}
