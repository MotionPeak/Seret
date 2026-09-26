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

    // MARK: - Which style, and how long it stays up

    @Test func windowedShowsTheTwoRowPanel() {
        #expect(PlayerHUDStyle.current(isFullScreen: false) == .windowed)
    }

    @Test func fullScreenShowsTheCompactBar() {
        #expect(PlayerHUDStyle.current(isFullScreen: true) == .fullScreen)
    }

    @Test func windowedHidesAfterTheLongerDelay() {
        #expect(PlayerHUDMetrics.autoHideDelay(isFullScreen: false) == .seconds(2.9))
    }

    @Test func fullScreenHidesSooner() {
        #expect(PlayerHUDMetrics.autoHideDelay(isFullScreen: true) == .seconds(1.8))
    }

    // MARK: - The full-screen compact bar's own sizes (mockup 4's `.mini`, --h = 10 pt)

    @Test func theCompactBarNeverGrowsPastItsCap() {
        #expect(PlayerHUDMetrics.FullScreen.barWidth(windowWidth: 1000) == 700)
        #expect(PlayerHUDMetrics.FullScreen.barWidth(windowWidth: 3000) == 700)
    }

    @Test func aNarrowWindowKeepsTheCompactBarsMargins() {
        #expect(PlayerHUDMetrics.FullScreen.barWidth(windowWidth: 600) == 560)
    }

    @Test func theCompactBarIsFarSmallerThanTheWindowedPanel() {
        // The whole regression: the compact bar's controls must be visibly smaller than the
        // windowed panel's, not a copy of the same numbers.
        #expect(PlayerHUDMetrics.FullScreen.iconButton < PlayerHUDMetrics.iconButton)
        #expect(PlayerHUDMetrics.FullScreen.playButton < PlayerHUDMetrics.playButton)
        #expect(PlayerHUDMetrics.FullScreen.icon < PlayerHUDMetrics.icon)
        #expect(PlayerHUDMetrics.FullScreen.playIcon < PlayerHUDMetrics.playIcon)
    }

    @Test func anythingStackedAboveTheCompactBarClearsItNotTheWindowedPanel() {
        #expect(PlayerHUDMetrics.FullScreen.clearOfBar < PlayerHUDMetrics.clearOfBottomPanel)
    }
}
