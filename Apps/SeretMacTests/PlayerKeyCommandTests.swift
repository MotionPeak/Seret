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

    @Test func anyCommandControlOrOptionPressPassesThrough() {
        // ⌘F
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "f", modifiers: [.command]) == nil)
        // ⌃⌘F
        #expect(PlayerKeyCommand(key: KeyEquivalent("f"), characters: "f", modifiers: [.control, .command]) == nil)
        // ⌥←
        #expect(PlayerKeyCommand(key: .leftArrow, characters: "", modifiers: [.option]) == nil)
    }

    @Test func otherKeysAreIgnored() {
        #expect(PlayerKeyCommand(key: KeyEquivalent("q"), characters: "q", modifiers: []) == nil)
        #expect(PlayerKeyCommand(key: KeyEquivalent("1"), characters: "1", modifiers: []) == nil)
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
