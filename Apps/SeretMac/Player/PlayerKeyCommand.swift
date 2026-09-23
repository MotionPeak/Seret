import SwiftUI

/// What a keypress over the focused player root means, decoded once so `PlayerScreen` only ever
/// switches on intent. Any of ⌘/⌃/⌥ passes through untouched — the menu bar owns those (⌘W, ⌘Q,
/// ⌘[, ⌃⌘F…), and ⌥←/→ subtitle timing is M4.
enum PlayerKeyCommand: Equatable {
    case playPause
    case skip(Double)
    case volume(Int)
    case mute
    case toggleFullScreen
    case escape

    init?(key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch key {
        case .space: self = .playPause
        case .leftArrow: self = .skip(-10)
        case .rightArrow: self = .skip(10)
        case .upArrow: self = .volume(10)
        case .downArrow: self = .volume(-10)
        case .escape: self = .escape
        default:
            switch characters.lowercased() {
            case "k": self = .playPause
            case "m": self = .mute
            case "f": self = .toggleFullScreen
            default: return nil
            }
        }
    }
}

/// Esc's priority (spec §7.1): close whatever's on top first, then leave full screen, and only
/// then leave the player.
enum PlayerEscape: Equatable {
    case closePanel, exitFullScreen, closePlayer

    static func next(panelOpen: Bool, isFullScreen: Bool) -> Self {
        if panelOpen { return .closePanel }
        if isFullScreen { return .exitFullScreen }
        return .closePlayer
    }
}

/// Mute remembers the volume it silenced and hands it back on un-mute. A volume of 0 remembered
/// from a mute restores to 100 rather than back to 0 (which would look like un-mute did nothing).
struct MuteMemory: Equatable {
    private(set) var restoreTo: Int?
    private(set) var isMuted = false

    /// Toggles mute and returns the volume that should be applied.
    mutating func toggle(current: Int) -> Int {
        if isMuted {
            let restore = restoreTo ?? 100
            isMuted = false
            restoreTo = nil
            return restore == 0 ? 100 : restore
        } else {
            restoreTo = current
            isMuted = true
            return 0
        }
    }

    /// A direct volume change (↑/↓ or the slider) cancels a pending mute — the volume just moved
    /// on its own, so there is nothing left to "restore" to.
    mutating func unmuteForVolumeChange() {
        isMuted = false
        restoreTo = nil
    }
}
