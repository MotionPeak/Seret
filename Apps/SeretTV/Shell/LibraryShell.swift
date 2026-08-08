import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: an HBO-style left side menu over the switched content. The menu is a
/// full-height overlay — content is inset by the collapsed rail and never moves when the menu
/// opens. One root NavigationStack OUTSIDE the content so Detail / the player still cover
/// everything cleanly.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var tab: SideMenuItem = .home
    @State private var path = NavigationPath()
    @State private var showingProfiles = false
    @FocusState private var menuFocus: SideMenuItem?


    /// Whether the panel is widened.
    ///
    /// Deliberately NOT derived from `menuFocus`. tvOS parks focus on this rail unprompted (it is
    /// the top-leading view) and will not hand focus back to the page afterwards — `@FocusState`
    /// writes, `resetFocus(in:)` + `prefersDefaultFocus`, and disabling the menu were all tried and
    /// ignored. So focus-presence would mean the menu sat open at launch and stayed open over the
    /// page you just picked.
    ///
    /// The signal that works is a *user action*, not a focus event: `.onMoveCommand` fires only
    /// when someone actually presses a direction, which tvOS's own focus bookkeeping never does.
    /// Gated on `menuFocus != nil` because that command also arrives from the profile picker on the
    /// way in. Collapsing is not a move command, so nothing re-opens the menu behind your back.
    @State private var menuExpanded = false
    /// The page has held focus at least once. Distinguishes a real navigation INTO the menu from
    /// tvOS parking focus on the rail at launch — see the `menuFocus` change handler.
    @State private var pageHasHeldFocus = false

    private var menuOpen: Bool { menuExpanded }

    /// Search needs a kind and the menu has none — take the section the user is browsing.
    private var searchKind: MediaKind { tab == .shows ? .show : .movie }

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $path) {
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Content clears the rail. This sits on the ROOT content only — pushed
                    // destinations are separate views and stay full-bleed.
                    .padding(.leading, SideMenu.railWidth)
                    .navigationDestination(for: BrowseDestination.self) { dest in
                        switch dest {
                        case .detail(let item): detailDestination(item)
                        case .add(let hit): AddScreen(hit: hit)
                        case .search(let kind): SearchScreen(kind: kind)
                        case .versions(let hit): VersionsScreen(hit: hit)
                        }
                    }
                    .navigationDestination(for: SearchHit.self) { hit in
                        AddScreen(hit: hit)
                    }
                    .navigationDestination(for: MediaItem.self) { item in
                        detailDestination(item)
                    }
                    .navigationDestination(for: PlaybackRequest.self) { request in
                        let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
                        if let model = session.makePlayer(for: request, engine: engine) {
                            PlayerView(model: model, engine: engine,
                                       backdropURL: TMDBClient.imageURL(path: request.item.backdropPath, size: "original"))
                        } else {
                            PlaybackUnavailableView()
                        }
                    }
            }
            // The menu hides while a Detail/Player is pushed so those stay full-screen.
            if path.isEmpty {
                SideMenuScrim(visible: menuOpen)
                SideMenu(selected: tab,
                         profileName: session.activeProfiles?.activeProfile?.name ?? "Profile",
                         profileAvatar: session.activeProfiles?.activeProfile?.avatar ?? "",
                         profileColorTag: session.activeProfiles?.activeProfile?.colorTag ?? "gold",
                         focus: $menuFocus,
                         expanded: menuExpanded,
                         onSelect: select,
                         onProfile: { showingProfiles = true })
                // A directional press WHILE the menu holds focus = the user is navigating it, so
                // widen. Both halves matter: a move command alone also arrives from the profile
                // picker on the way in (which would open the menu at launch), and focus alone is
                // what tvOS hands the rail unprompted.
                .onMoveCommand { _ in if menuFocus != nil { menuExpanded = true } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        // Menu button opens the nav from anywhere; a second press falls through and exits, because
        // the handler is removed while the menu is already open.
        .onExitCommand(perform: menuOpen || !path.isEmpty ? nil : {
            menuFocus = tab
            menuExpanded = true
        })
        // Focus ENTERING the menu opens it; focus leaving collapses it.
        //
        // The entry half is what fixes "I have to swipe left twice". `.onMoveCommand` above only
        // fires while the menu ALREADY holds focus, so the first press from a page — the one the
        // focus engine spends moving focus into the rail — was invisible to it, and the menu stayed
        // a collapsed strip with a focused row inside it until you pressed again.
        //
        // `pageHasHeldFocus` is what keeps this from re-creating the bug it replaced: tvOS parks
        // focus on this rail unprompted at launch (it is the top-leading view), and expanding on
        // that would open the menu over the page before the viewer touched anything. A focus entry
        // only counts once the PAGE has held focus, which can only happen after a real navigation.
        .onChange(of: menuFocus) { _, new in
            if new == nil {
                pageHasHeldFocus = true
                menuExpanded = false
            } else if pageHasHeldFocus {
                menuExpanded = true
            }
        }
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
        .onChange(of: tab) { _, new in if new == .home { Task { await session.refreshHome() } } }
        .onChange(of: path.isEmpty) { _, empty in if empty { Task { await session.refreshHome() } } }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
    }

    /// Search pushes, the profile presents, everything else switches the page. Commit-on-press —
    /// focusing a row only highlights it, so gliding the remote never rebuilds a page.
    private func select(_ item: SideMenuItem) {
        switch item {
        case .search:  path.append(BrowseDestination.search(searchKind))
        case .profile: showingProfiles = true
        default:
            tab = item
            menuExpanded = false   // collapse onto the page you just chose
        }
    }

    /// The library Detail for a pushed item (shared by the MediaItem and BrowseDestination routes).
    @ViewBuilder private func detailDestination(_ item: MediaItem) -> some View {
        if let details = session.detailsProvider {
            DetailView(item: item, details: details, watch: session.watchStore,
                       profileID: session.activeProfileID,
                       myList: session.myListStore,
                       ratings: session.ratingsProvider,
                       versionPrefs: session.versionPreferences)
        }
    }

    /// Pages stay alive across switches (instant, no rebuild → snappy). Movies/Shows are separate
    /// browse surfaces now, so each keeps its own segment + genre state. The whole area is one
    /// focus section so travel between the menu and a page is unambiguous.
    @ViewBuilder private var pages: some View {
        ZStack {
            keptAlive(tab == .home) { HomeScreen() }
            keptAlive(tab == .movies) { BrowseScreen(kind: .movie) }
            keptAlive(tab == .shows) { BrowseScreen(kind: .show) }
            keptAlive(tab == .library) { MyLibraryScreen() }
            if tab == .settings { SettingsView() }
        }
        .focusSection()
    }

    @ViewBuilder private func keptAlive<V: View>(_ visible: Bool, @ViewBuilder _ make: () -> V) -> some View {
        make()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }
}

/// Shown only if a player can't be built while signed in (e.g. the SwiftData container failed).
/// Gives the user a way back instead of a soft-locked blank screen.
private struct PlaybackUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
            Text("Unable to start playback.").font(.seretTitle2)
            Button("Back") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { dismiss() }
    }
}
