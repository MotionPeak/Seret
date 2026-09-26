import SwiftUI
import Testing
@testable import Seret

@Suite struct PlayerKeyCommandTests {
    @Test func spaceAndKPlayOrPause() {
        #expect(PlayerKeyCommand(key: .space, characters: " ", modifiers: []) == .playPause)
        #expect(PlayerKeyCommand(key: KeyEquivalent("k"), characters: "k", modifiers: []) == .playPause)
        #expect(PlayerKeyCommand(key: KeyEquivalent("K"), characters: "K", modifiers: [.shift]) == .playPause)
    }

    @Test func arrowsSkipTenSeconds() {
        #expect(PlayerKeyCommand(key: .leftArrow, characters: "", modifiers: []) == .skip(-10))
        #expect(PlayerKeyCommand(key: .rightArrow, characters: "", modifiers: []) == .skip(10))
    }

    @Test func upAndDownChangeVolumeByTen() {
        #expect(PlayerKeyCommand(key: .upArrow, characters: "", modifiers: []) == .volume(10))
        #expect(PlayerKeyCommand(key: .downArrow, characters: "", modifiers: []) == .volume(-10))
    }

    @Test func mAndFAreCaseInsensitive() {
        #expect(PlayerKeyCommand(key: KeyEquivalent("m"), characters: "m", modifiers: []) == .mute)
        #expect(PlayerKeyCommand(key: KeyEquivalent("M"), characters: "M", modifiers: [.shift]) == .mute)
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "f", modifiers: []) == .toggleFullScreen)
        #expect(PlayerKeyCommand(key: KeyEquivalent("F"), characters: "F", modifiers: [.shift]) == .toggleFullScreen)
    }

    @Test func commandAndControlPressesPassThrough() {
        // ⌘F
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "f", modifiers: [.command]) == nil)
        // ⌃⌘F
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "f", modifiers: [.control, .command]) == nil)
        // ⌘← (Back) belongs to the menu
        #expect(PlayerKeyCommand(key: .leftArrow, characters: "", modifiers: [.command]) == nil)
    }

    @Test func optionArrowsNudgeTheSubtitleHalfASecond() {
        #expect(PlayerKeyCommand(key: .leftArrow, characters: "", modifiers: [.option]) == .subtitleDelay(-0.5))
        #expect(PlayerKeyCommand(key: .rightArrow, characters: "", modifiers: [.option]) == .subtitleDelay(0.5))
        // ⌥ on anything else is not ours
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "ƒ", modifiers: [.option]) == nil)
    }

    @Test func panelsEpisodesAndSpeedKeys() {
        #expect(PlayerKeyCommand(key: KeyEquivalent("s"), characters: "s", modifiers: []) == .toggleTracks)
        #expect(PlayerKeyCommand(key: KeyEquivalent("E"), characters: "E", modifiers: [.shift]) == .toggleEpisodes)
        #expect(PlayerKeyCommand(key: KeyEquivalent("n"), characters: "n", modifiers: []) == .nextEpisode)
        #expect(PlayerKeyCommand(key: KeyEquivalent("["), characters: "[", modifiers: []) == .speed(-1))
        #expect(PlayerKeyCommand(key: KeyEquivalent("]"), characters: "]", modifiers: []) == .speed(1))
    }

    @Test func digitsRateOneToTenWithZeroAsTen() {
        #expect(PlayerKeyCommand(key: KeyEquivalent("1"), characters: "1", modifiers: []) == .rate(1))
        #expect(PlayerKeyCommand(key: KeyEquivalent("9"), characters: "9", modifiers: []) == .rate(9))
        #expect(PlayerKeyCommand(key: KeyEquivalent("0"), characters: "0", modifiers: []) == .rate(10))
    }

    @Test func otherKeysAreIgnored() {
        #expect(PlayerKeyCommand(key: KeyEquivalent("q"), characters: "q", modifiers: []) == nil)
        #expect(PlayerKeyCommand(key: KeyEquivalent("z"), characters: "z", modifiers: []) == nil)
    }

    @Test func speedStepsWalkTheListAndStopAtTheEnds() {
        #expect(PlaybackSpeeds.step(from: 1.0, direction: 1) == 1.25)
        #expect(PlaybackSpeeds.step(from: 1.0, direction: -1) == 0.75)
        #expect(PlaybackSpeeds.step(from: 1.5, direction: 1) == 1.5)
        #expect(PlaybackSpeeds.step(from: 0.5, direction: -1) == 0.5)
        // an off-list rate snaps to its nearest neighbour first
        #expect(PlaybackSpeeds.step(from: 1.1, direction: 1) == 1.25)
        #expect(PlaybackSpeeds.label(1) == "Normal")
        #expect(PlaybackSpeeds.label(1.25) == "1.25×")
    }

    @Test func manualSyncKeys() {
        #expect(ManualSyncKey(key: .upArrow, modifiers: []) == .moveLine(-1))
        #expect(ManualSyncKey(key: .downArrow, modifiers: []) == .moveLine(1))
        #expect(ManualSyncKey(key: .return, modifiers: []) == .mark)
        #expect(ManualSyncKey(key: .leftArrow, modifiers: []) == .nudge(-0.1))
        #expect(ManualSyncKey(key: .rightArrow, modifiers: []) == .nudge(0.1))
        #expect(ManualSyncKey(key: .escape, modifiers: []) == .done)
        #expect(ManualSyncKey(key: .leftArrow, modifiers: [.option]) == nil)
    }

    @Test func escapeEndsASyncSessionBeforeAnythingElse() {
        #expect(PlayerEscape.next(syncActive: true, panelOpen: true, isFullScreen: true) == .endSync)
    }

    @Test func escapeClosesThePanelFirst() {
        #expect(PlayerEscape.next(panelOpen: true, isFullScreen: true) == .closePanel)
        #expect(PlayerEscape.next(panelOpen: true, isFullScreen: false) == .closePanel)
    }

    @Test func escapeThenLeavesFullScreen() {
        #expect(PlayerEscape.next(panelOpen: false, isFullScreen: true) == .exitFullScreen)
    }

    @Test func escapeFinallyClosesThePlayer() {
        #expect(PlayerEscape.next(panelOpen: false, isFullScreen: false) == .closePlayer)
    }

    @Test func muteRemembersAndRestores() {
        var memory = MuteMemory()
        #expect(memory.toggle(current: 60) == 0)
        #expect(memory.isMuted)
        #expect(memory.toggle(current: 0) == 60)
        #expect(!memory.isMuted)
    }

    @Test func unmutingFromZeroRestoresFull() {
        var memory = MuteMemory()
        #expect(memory.toggle(current: 0) == 0)          // muting an already-silent volume
        #expect(memory.toggle(current: 0) == 100)         // un-muting restores to full, not to 0
    }
}
