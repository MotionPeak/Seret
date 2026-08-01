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

    /// The panel is widened exactly while focus is inside it — "the menu is open while you are in
    /// it". Press Left from a page to open it, Right (or any move into content) to close it.
    ///
    /// ⚠️ Known gap: selecting a row leaves focus ON that row, so the menu stays open over the page
    /// you just chose until you press Right. HBO Max collapses there. Handing focus back to the page
    /// needs a programmatic focus move, and tvOS ignores a `@FocusState` write from here — tried on
    /// the same turn, deferred one turn, deferred 150ms, and with a per-page keyed anchor (several
    /// pages are alive at once, so a shared Bool is ambiguous). Driving expansion from explicit state
    /// instead does not help: the collapse animation re-fires the focus change and re-opens it, and
    /// a focus event cannot be told apart from tvOS's own initial pick.
    private var menuOpen: Bool { menuFocus != nil }

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
                         onSelect: select,
                         onProfile: { showingProfiles = true })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        // Menu button opens the nav from anywhere; a second press falls through and exits, because
        // the handler is removed while the menu is already open.
        .onExitCommand(perform: menuOpen || !path.isEmpty ? nil : { menuFocus = tab })
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
