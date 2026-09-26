import SwiftUI

/// What a keypress over the focused player root means, decoded once so `PlayerScreen` only ever
/// switches on intent. ⌘ and ⌃ always pass through — the menu bar owns those (⌘W, ⌘Q, ⌘[, ⌃⌘F…).
/// ⌥ is ours only on ←/→ (subtitle timing, spec §7.3); anything else with ⌥ passes through too.
enum PlayerKeyCommand: Equatable {
    case playPause
    case skip(Double)
    case volume(Int)
    case mute
    case toggleFullScreen
    case escape
    /// ⌥←/⌥→ — nudge the subtitle half a second earlier/later.
    case subtitleDelay(Double)
    /// S — the Audio & Subtitles panel.
    case toggleTracks
    /// E — the episode strip.
    case toggleEpisodes
    /// N — the next episode.
    case nextEpisode
    /// [ and ] — one speed step down/up.
    case speed(Double)
    /// 1…9 and 0 (= 10) — only acted on while the credits rating bar is up.
    case rate(Int)

    init?(key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control]) else { return nil }
        if modifiers.contains(.option) {
            switch key {
            case .leftArrow: self = .subtitleDelay(-0.5)
            case .rightArrow: self = .subtitleDelay(0.5)
            default: return nil
            }
            return
        }
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
            case "s": self = .toggleTracks
            case "e": self = .toggleEpisodes
            case "n": self = .nextEpisode
            case "[": self = .speed(-1)
            case "]": self = .speed(1)
            case "0": self = .rate(10)
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                guard let value = Int(characters) else { return nil }
                self = .rate(value)
            default: return nil
            }
        }
    }
}

/// Keys while a "Sync to a line" session is open (spec §7.4): ↑↓ pick the line, Return marks the
/// moment it was heard, ←→ nudge the result by a tenth of a second, Esc finishes.
enum ManualSyncKey: Equatable {
    case moveLine(Int)
    case mark
    case nudge(Double)
    case done

    init?(key: KeyEquivalent, modifiers: EventModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch key {
        case .upArrow: self = .moveLine(-1)
        case .downArrow: self = .moveLine(1)
        case .return, .space: self = .mark
        case .leftArrow: self = .nudge(-0.1)
        case .rightArrow: self = .nudge(0.1)
        case .escape: self = .done
        default: return nil
        }
    }
}

/// The playback speeds `[`/`]` step through — the same five the panel offers.
enum PlaybackSpeeds {
    static let all: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]

    static func label(_ rate: Double) -> String {
        rate == 1 ? "Normal" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    /// One step from `current` (snapped to the nearest listed speed) in `direction`'s sign,
    /// clamped to the ends.
    static func step(from current: Double, direction: Double) -> Double {
        let nearest = all.indices.min { abs(all[$0] - current) < abs(all[$1] - current) } ?? 2
        let next = nearest + (direction > 0 ? 1 : -1)
        return all[min(max(next, 0), all.count - 1)]
    }
}

/// Esc's priority (spec §7.1): a sync session first, then whatever panel is open, then full screen,
/// and only then the player.
enum PlayerEscape: Equatable {
    case endSync, closePanel, exitFullScreen, closePlayer

    static func next(syncActive: Bool = false, panelOpen: Bool, isFullScreen: Bool) -> Self {
        if syncActive { return .endSync }
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
