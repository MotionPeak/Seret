import SwiftUI

/// Turns a raw key press on the title page into a 1–10 personal rating.
enum RatingKey {
    /// The unmodified digits `1`…`9` rate 1–9 and `0` rates 10. Any of ⌘/⌥/⌃ held passes the key
    /// through untouched (nil), so ⌘1…⌘5 still switch sidebar sections.
    static func value(for characters: String, modifiers: EventModifiers) -> Int? {
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        guard characters.count == 1, let c = characters.first, c.isASCII,
              let digit = c.wholeNumberValue, (0...9).contains(digit)
        else { return nil }
        return digit == 0 ? 10 : digit
    }

    /// Pressing the currently-set rating again clears it (tvOS `UserRatingRow` rule).
    static func next(current: Int?, pressed: Int) -> Int? {
        current == pressed ? nil : pressed
    }
}
