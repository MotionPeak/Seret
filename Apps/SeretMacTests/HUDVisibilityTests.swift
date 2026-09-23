import Testing
@testable import Seret

@MainActor
@Suite struct HUDVisibilityTests {
    @Test func hidesWhenPlayingAndIdle() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.hideIfAllowed()
        #expect(!hud.isVisible)
    }

    @Test func staysWhilePaused() {
        let hud = HUDVisibility(delay: nil)
        hud.hideIfAllowed()
        #expect(hud.isVisible)
    }

    @Test func staysWhileThePointerIsOnTheControls() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.pointerOverControls = true
        hud.hideIfAllowed()
        #expect(hud.isVisible)
    }

    @Test func staysWhileAPanelIsOpen() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.panelOpen = true
        hud.hideIfAllowed()
        #expect(hud.isVisible)
    }

    @Test func staysWhileScrubbing() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.isScrubbing = true
        hud.hideIfAllowed()
        #expect(hud.isVisible)
    }

    @Test func pokeShowsIt() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.hideIfAllowed()
        #expect(!hud.isVisible)
        hud.poke()
        #expect(hud.isVisible)
    }

    @Test func pausingShowsIt() {
        let hud = HUDVisibility(delay: nil)
        hud.isPlaying = true
        hud.hideIfAllowed()
        #expect(!hud.isVisible)
        hud.isPlaying = false
        #expect(hud.isVisible)
    }

    @Test func aPinnedHUDNeverArmsATimer() {
        let hud = HUDVisibility(delay: nil)
        hud.poke()
        #expect(!hud.isTimerArmedForTesting)
    }

    @Test func windowedArmsTheLongerDelay() {
        let hud = HUDVisibility()
        hud.poke()
        #expect(hud.armedDelayForTesting == .seconds(2.9))
    }

    @Test func fullScreenArmsTheShorterDelay() {
        let hud = HUDVisibility()
        hud.isFullScreen = true
        hud.poke()
        #expect(hud.armedDelayForTesting == .seconds(1.8))
    }

    @Test func aPinnedHUDNeverArmsATimerEvenInFullScreen() {
        let hud = HUDVisibility(delay: nil)
        hud.isFullScreen = true
        hud.poke()
        #expect(!hud.isTimerArmedForTesting)
    }
}
