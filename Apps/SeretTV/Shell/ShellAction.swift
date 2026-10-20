import SwiftUI

/// Something the shell does for a view anywhere under it — push a page, ask to remove a title —
/// handed down the environment as ONE object for the shell's life.
///
/// ⚠️ Not a closure. A closure environment value is a new value every time the shell's body runs,
/// and SwiftUI cannot tell two closures apart, so every view that read it re-rendered with the
/// shell: every `BrowseTile` on Home, Movies and Shows (kept-alive pages included) on every press
/// in the side menu, which re-runs the shell. Measured on the real Apple TV as the menu's lag. The
/// object stays the same; only the work it forwards to is refreshed.
///
/// Not main-actor isolated as a type so it can be an `EnvironmentKey` default; every use is on the
/// main actor.
final class ShellAction<Input>: @unchecked Sendable {
    private var perform: @MainActor (Input) -> Void

    init(_ perform: @escaping @MainActor (Input) -> Void = { _ in }) {
        self.perform = perform
    }

    /// Points the action at the shell's current state. Called from the shell's body; it is not
    /// observed, so it never re-renders anything.
    @MainActor func set(_ perform: @escaping @MainActor (Input) -> Void) {
        self.perform = perform
    }

    @MainActor func callAsFunction(_ input: Input) {
        perform(input)
    }
}

/// Whether the side menu holds focus, as one object for the shell's life. Pages that move focus by
/// themselves (handing focus on from a removed tile) check it when they act. A `Bool` in the
/// environment re-rendered Home and the Watchlist — rebuilding every row — each time focus went
/// into or out of the menu.
final class SideMenuFocusFlag: @unchecked Sendable {
    @MainActor var holdsFocus = false
}
