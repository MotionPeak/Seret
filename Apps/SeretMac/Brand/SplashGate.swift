import DebridUI
import Foundation

/// When the splash may come down. Pure so the launch race (animation vs. sign-in vs. the first
/// library load, all running concurrently) is testable without booting the app.
///
/// The splash used to hold for a fixed 1.6 s regardless of what was happening underneath — long
/// enough on a fast connection, and not nearly long enough on a slow one, where the shell appeared
/// with an empty grid that then populated a beat later. This instead waits for the thing the
/// shell actually needs: a signed-out viewer needs nothing, and a signed-in one needs the
/// library's first answer — loaded, empty or failed all count, since each is something the shell
/// can render. A cap keeps a wedged load from holding the splash forever.
enum SplashGate {
    static let maxHold: Duration = .seconds(6)

    /// Hide once the animation has run AND (signed out, OR the library has answered, OR it has
    /// been held `maxHold` since the animation ended).
    static func shouldHide(animationFinished: Bool, session: AppSession.State,
                           library: LibraryStore.State?, heldFor: Duration) -> Bool {
        guard animationFinished else { return false }
        if session == .signedOut { return true }
        if let library, libraryHasAnswered(library) { return true }
        return heldFor >= maxHold
    }

    private static func libraryHasAnswered(_ state: LibraryStore.State) -> Bool {
        switch state {
        case .loading: return false
        case .loaded, .empty, .failed: return true
        }
    }
}
