import CoreGraphics
import DebridCore
import DebridUI
import Foundation
import Observation
import SwiftUI

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
        // A sidebar row always leaves Search. The row the viewer was already on just brings its
        // section back exactly as it was (it is not also a "pop to root" while Search covers it).
        if isSearching {
            exitSearch()
            selection = section
            return
        }
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

    /// The history the window is showing: Search's own while searching, else the selected
    /// section's. Every push, pop and "what is on top" goes through these two.
    private var activeHistory: NavigationHistory { isSearching ? searchHistory : history(for: selection) }

    private func updateActiveHistory(_ change: (inout NavigationHistory) -> Void) {
        if isSearching {
            change(&searchHistory)
        } else {
            change(&histories[selection, default: NavigationHistory()])
        }
    }

    /// Pushes on the SELECTED section's history — every push starts from wherever the viewer is.
    /// Decision 10: a poster tile sets `pendingFlightSource` immediately before this call (both the
    /// click and the menu's Open take the same path), and it is ALWAYS consumed here, whether or
    /// not the push actually flies — a stale source must never survive to the next open.
    func open(_ route: AppRoute) {
        let source = pendingFlightSource
        pendingFlightSource = nil
        var newFlight: HeroFlight?
        if case .title(let item) = route {
            let target = HeroFlightGeometry.backdropFrame(window: windowSize)
            let plan = HeroFlightGeometry.plan(source: source?.frame, target: target,
                                               window: windowSize, reduceMotion: reduceMotion)
            if case .fly(let from, let to) = plan, let source {
                titleSources[item.id] = source.tileID
                newFlight = HeroFlight(direction: .forward, routeID: item.id, from: from, to: to,
                                       posterURL: source.posterURL, backdropURL: backdropURL(for: item),
                                       tileID: source.tileID)
            }
        }
        // Explicitly replaces (or clears) any old flight — a stale landed flight from an earlier
        // title must never leak into a push it has nothing to do with (e.g. opening a Person page).
        flight = newFlight
        // A NavigationStack push animates its own slide by default — while a flight runs, only the
        // flyer itself should move (the "push itself" note in Task 8).
        withTransaction(newFlight == nil ? Transaction() : Transaction(animation: nil)) {
            updateActiveHistory { $0.push(route) }
        }
        if isSearching { searchBlurRequest += 1 }
    }

    /// Pops the SELECTED section's history. When the top route is a title this flew in from a still
    /// -reachable tile, it flies back to that tile's LATEST reported frame (Decision 10) — the tile
    /// may have moved under scrolling since the forward flight landed. Anything else (no flight ever
    /// happened, or the tile is gone) just pops, and the page's own cross-fade is the whole transition.
    func goBack() {
        // Back from the results leaves Search: the section underneath is exactly as it was.
        if isSearching, searchHistory.path.isEmpty {
            exitSearch()
            return
        }
        var newFlight: HeroFlight?
        if case .title(let item)? = activeHistory.path.last,
           let tileID = titleSources[item.id], let sourceFrame = tileFrames[tileID], let heroFrame {
            let plan = HeroFlightGeometry.plan(source: sourceFrame, target: heroFrame,
                                               window: windowSize, reduceMotion: reduceMotion)
            if case .fly(let from, let to) = plan {
                newFlight = HeroFlight(direction: .back, routeID: item.id, from: from, to: to,
                                       posterURL: posterURL(for: item), backdropURL: backdropURL(for: item),
                                       tileID: tileID)
            }
        }
        flight = newFlight
        withTransaction(newFlight == nil ? Transaction() : Transaction(animation: nil)) {
            updateActiveHistory { $0.back() }
        }
    }

    func goForward() { updateActiveHistory { $0.forward() } }
    /// Search can always step back — out of it, from its results.
    var canGoBack: Bool { isSearching || history(for: selection).canGoBack }
    var canGoForward: Bool { activeHistory.canGoForward }

    // MARK: - Surprise Me

    /// The Surprise Me reel, shown by the shell ABOVE everything — the sidebar included — so the
    /// reel is centred on the window and nothing shows through beside it.
    struct SurprisePresentation: Identifiable {
        var spin: WatchlistRandomizer.Spin
        /// Another spin of the same watchlist (Spin Again).
        let respin: () -> WatchlistRandomizer.Spin?
        var id: UUID { spin.id }
    }
    var surprise: SurprisePresentation?

    // MARK: - Hero flight (Task 8)

    /// Set only by `open`/`back`/the flight driver (and the DEBUG harness's `previewPinFlight`).
    var flight: HeroFlight?
    /// Every VISIBLE poster tile's own frame, in window coordinates — written by the tile itself on
    /// every layout pass. Deliberately unobserved (Decision 10): a `@Published`-style dictionary
    /// here would re-run on every scroll frame of every grid and rail; nothing ever reads this
    /// through SwiftUI's observation, only `open`/`goBack`/a tile's own `isFlightSource` check.
    @ObservationIgnored var tileFrames: [UUID: CGRect] = [:]
    /// The visible title hero's own frame, in window coordinates — reported the same way, so `back`
    /// starts from where the hero really is after scrolling, not where it was when the page opened.
    @ObservationIgnored var heroFrame: CGRect?
    @ObservationIgnored var windowSize: CGSize = .zero
    @ObservationIgnored var reduceMotion = false
    /// Set by a poster tile immediately before it calls `open(.title(...))` — the click and the
    /// menu's Open both take this path. `open` always consumes it, whether or not it ends up flying.
    @ObservationIgnored var pendingFlightSource: FlightSource?
    /// Which tile a title (by `item.id`) flew in from, so `goBack()` can look that tile up again.
    @ObservationIgnored private var titleSources: [String: UUID] = [:]

    private func posterURL(for item: MediaItem) -> URL? {
        TMDBClient.imageURL(path: item.posterPath, size: "w342")
    }

    private func backdropURL(for item: MediaItem) -> URL? {
        TMDBClient.imageURL(path: item.backdropPath ?? item.posterPath, size: "w1280")
    }

    /// What a title page's hero and its own sections read to stay hidden until the flight that
    /// brought THEM here lands — `false` the instant it lands, and just as `false` when there was
    /// never a flight at all (a direct push, or a cross-fade), so the page shows normally either way.
    func isFlightLanding(for routeID: String) -> Bool {
        guard let flight, flight.routeID == routeID, flight.direction == .forward else { return false }
        return !flight.landed
    }

    /// `HeroFlightLayer`'s completion callback: a stale id (a flight since replaced) is ignored.
    /// Forward marks `landed` so the real hero can take over while the flyer's final frame still
    /// matches it exactly; back simply clears the flight — the real tile underneath is what shows.
    func landFlight(_ id: UUID) {
        guard flight?.id == id else { return }
        switch flight?.direction {
        case .forward: flight?.landed = true
        case .back, nil: flight = nil
        }
    }

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

    /// Replaces any current presentation with a new one (a fresh id even for the same request),
    /// and closes any full-window trailer that happens to be up — the two overlays never coexist.
    func present(_ request: PlaybackRequest) {
        playback = PlaybackPresentation(request: request)
        trailer = nil
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

    // MARK: - Trailer overlay (Task 4)

    struct TrailerPresentation: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
    }

    private(set) var trailer: TrailerPresentation?

    /// No-op while playback is up — a "Watch Trailer" tap racing a Play the viewer already
    /// started must not throw a second overlay on top of the player.
    func presentTrailer(_ url: URL, title: String) {
        guard playback == nil else { return }
        trailer = TrailerPresentation(url: url, title: title)
    }

    func closeTrailer() {
        trailer = nil
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

    /// Pops the SELECTED section's history once, but only when `id` is the route on top of it —
    /// what a title page's own "Remove from Library…" needs once removal succeeds (a poster's
    /// removal, from some OTHER page, must never pop whatever the viewer is looking at now).
    func popTitleIfShowing(_ id: String) {
        guard case .title(let top)? = activeHistory.path.last, top.id == id else { return }
        goBack()
    }
    /// "Couldn't Remove" alert message, set when a confirmed removal fails.
    var removalError: String?
    /// "Couldn't Play" alert target, set when a poster's Play finds nothing playable.
    var couldNotPlay: MediaItem?

    // MARK: - Add by Magnet (Task 5)

    /// Bumped by File ▸ Add by Magnet… (⇧⌘M) and by every in-page "Add by Magnet…" control alike —
    /// one mechanism, the same pattern as `searchFocusRequest`. The visible title page opens its
    /// sheet on change; it is the one that decides whether it is the page this counter is for.
    private(set) var magnetRequest = 0

    func requestMagnet() { magnetRequest += 1 }

    /// The selected section's top route, when it is a title page — what `magnetRequest` and a
    /// poster's removal both need to know "is the page I'd affect actually the one showing".
    var titleOnTop: MediaItem? {
        guard case .title(let top)? = activeHistory.path.last else { return nil }
        return top
    }

    // MARK: - Browse (Task 6 on)

    /// The genre each kind is currently showing — nil means **All**. A genre is an in-place filter
    /// on the Movies/Shows page, not a route, so it lives here rather than on the navigation path
    /// (Decision 5): it is remembered per kind and survives pushing a title and coming back.
    private(set) var browseGenre: [MediaKind: DiscoverStore.Genre] = [:]

    func setBrowseGenre(_ genre: DiscoverStore.Genre?, for kind: MediaKind) {
        browseGenre[kind] = genre
    }

    // MARK: - Search (Task 7 on)

    private(set) var searchQuery = ""
    var searchScope: SearchScope = .all
    /// Bumped by ⌘F / *Go ▸ Search* — `SearchField` focuses itself when this changes.
    private(set) var searchFocusRequest = 0

    func requestSearchFocus() { searchFocusRequest += 1 }

    /// True while the window shows Search: its own stack, over the selected section, which stays
    /// exactly as it was underneath. The results are the stack's root.
    private(set) var isSearching = false
    /// Pages opened FROM the results — back returns to them, back again leaves Search.
    private(set) var searchHistory = NavigationHistory()
    /// Bumped when a page is opened from the results, so the field lets go of the keyboard (a
    /// title page's 1–0 rating keys must reach the page, not the query).
    private(set) var searchBlurRequest = 0

    /// Typing never navigates: it only changes the query, shows Search if it isn't showing, and —
    /// when the viewer types a NEW query on a page opened from the results — returns to them.
    ///
    /// It used to push a `.search` page onto the section whenever one wasn't on top. The field
    /// re-sends its text when it loses focus (opening a result does exactly that), so it pushed a
    /// second search page over the title just opened, mid-transition — the stacked pages and the
    /// "can't go back" the owner hit.
    func setSearchQuery(_ text: String) {
        guard text != searchQuery else { return }   // a re-send is not typing
        searchQuery = text
        let isBlank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isBlank {
            if !isSearching {
                searchHistory = NavigationHistory()
                isSearching = true
            } else if !searchHistory.path.isEmpty {
                searchHistory.popToRoot()
            }
        } else if isSearching, searchHistory.path.isEmpty {
            exitSearch()
        }
    }

    /// Esc, the field's ✕, Back from the results, or any sidebar row.
    func exitSearch() {
        isSearching = false
        searchQuery = ""
        searchHistory = NavigationHistory()
    }

    /// The Search stack's `NavigationStack` binding.
    func setSearchPath(_ path: [AppRoute]) { searchHistory.setPath(path) }
}
