import DebridCore
import DebridUI
import Foundation
import Observation

/// One window's shell state: which section is showing and whether the sidebar is a rail.
/// Collapsing is remembered across launches. Also owns each section's back/forward history and
/// the (still unused before Task 4) playback presentation slot.
@MainActor
@Observable
final class ShellModel {
    var selection: SidebarSection = .home
    private(set) var isSidebarCollapsed: Bool
    private(set) var histories: [SidebarSection: NavigationHistory] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    private static let collapsedKey = "seret.mac.sidebarCollapsed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSidebarCollapsed = defaults.bool(forKey: Self.collapsedKey)
    }

    func toggleSidebar() {
        isSidebarCollapsed.toggle()
        defaults.set(isSidebarCollapsed, forKey: Self.collapsedKey)
    }

    /// Selecting the section already showing pops it to root — the sidebar row doubles as "back to
    /// the top". Selecting another section keeps every section's path exactly as it was.
    func select(_ section: SidebarSection) {
        if selection == section {
            histories[section, default: NavigationHistory()].popToRoot()
        } else {
            selection = section
        }
    }

    /// ⌘1…⌘5. A digit with no section is ignored.
    func select(shortcut digit: Int) {
        guard let section = SidebarSection.allCases.first(where: { $0.shortcutDigit == digit }) else { return }
        select(section)
    }

    // MARK: - Navigation

    func history(for section: SidebarSection) -> NavigationHistory { histories[section] ?? NavigationHistory() }

    func setPath(_ path: [AppRoute], for section: SidebarSection) {
        histories[section, default: NavigationHistory()].setPath(path)
    }

    /// Pushes on the SELECTED section's history — every push starts from wherever the viewer is.
    func open(_ route: AppRoute) {
        histories[selection, default: NavigationHistory()].push(route)
    }

    func goBack() { histories[selection, default: NavigationHistory()].back() }
    func goForward() { histories[selection, default: NavigationHistory()].forward() }
    var canGoBack: Bool { history(for: selection).canGoBack }
    var canGoForward: Bool { history(for: selection).canGoForward }

    // MARK: - Playback slot (Task 4 on)

    struct PlaybackPresentation: Identifiable, Equatable {
        let id = UUID()
        let request: PlaybackRequest
    }

    private(set) var playback: PlaybackPresentation?
    /// Bumped once a closed player has STOPPED AND WRITTEN its final position (not when it merely
    /// leaves the screen — teardown is async, and a page that re-read watch state at dismissal
    /// raced that last write and could show the previous Resume time). Pages re-read on change.
    private(set) var playbackEndedCount = 0

    /// Replaces any current presentation with a new one (a fresh id even for the same request).
    func present(_ request: PlaybackRequest) {
        playback = PlaybackPresentation(request: request)
    }

    /// Takes the player off screen. Watch state is re-read later, by `playerDidTearDown()`.
    func endPlayback() {
        playback = nil
    }

    /// Called by the player after `PlayerModel.teardown()` has returned (engine stopped, final
    /// progress recorded) — once per presentation.
    func playerDidTearDown() {
        playbackEndedCount += 1
    }

    // MARK: - Shared confirmations, alerts and toast (Task 2 on)

    struct ShellToast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isFailure: Bool
    }

    private(set) var toast: ShellToast?
    /// How long the current toast should linger before `ShellToastView`'s own timer dismisses it.
    /// `nil` pins the toast on screen — the harness only, so a screenshot never races the fade.
    private(set) var toastLingers: Duration?

    func showToast(_ message: String, isFailure: Bool = false, lingers: Duration? = .seconds(2.6)) {
        toast = ShellToast(message: message, isFailure: isFailure)
        toastLingers = lingers
    }

    /// No-op unless `id` is still the current toast — a stale timer firing after a newer toast
    /// replaced it must not dismiss the new one.
    func dismissToast(_ id: UUID) {
        guard toast?.id == id else { return }
        toast = nil
    }

    /// Set by any poster's "Remove from Library…" — drives the shared confirmation alert.
    var pendingRemoval: MediaItem?
    /// "Couldn't Remove" alert message, set when a confirmed removal fails.
    var removalError: String?
    /// "Couldn't Play" alert target, set when a poster's Play finds nothing playable.
    var couldNotPlay: MediaItem?

    // MARK: - Browse (Task 6 on)

    /// The genre each kind is currently showing — nil means **All**. A genre is an in-place filter
    /// on the Movies/Shows page, not a route, so it lives here rather than on the navigation path
    /// (Decision 5): it is remembered per kind and survives pushing a title and coming back.
    private(set) var browseGenre: [MediaKind: DiscoverStore.Genre] = [:]

    func setBrowseGenre(_ genre: DiscoverStore.Genre?, for kind: MediaKind) {
        browseGenre[kind] = genre
    }
}
