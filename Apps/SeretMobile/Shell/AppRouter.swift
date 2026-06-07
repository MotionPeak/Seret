import Observation
import DebridCore
import DebridUI

/// App-level navigation state, hoisted ABOVE the adaptive shell (TabView / NavigationSplitView)
/// so the full-screen Detail (and the player nested in it) survive device rotation. A
/// `fullScreenCover` presented from *inside* a TabView/SplitView is dismissed by SwiftUI on
/// rotation; presenting it from the root view (RootView) fixes that.
@MainActor
@Observable
final class AppRouter {
    /// The title shown full-screen in Detail. Set from Home/Library; presented by RootView.
    var detail: MediaItem?

    /// The search hit shown full-screen in the Add flow. Set from Search; presented by RootView
    /// (above the TabView/SplitView, so it — and its nested player — survive rotation).
    var addHit: SearchHit?
}
