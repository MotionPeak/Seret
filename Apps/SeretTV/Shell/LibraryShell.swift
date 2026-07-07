import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: a custom Gold Glass top tab bar (Home · Find · My Library, with Settings
/// behind the gear) over the switched content. The tab bar switches ON PRESS (focus a pill, click to
/// select — moving focus never changes the page, so you can't skid past a section by accident).
/// One root NavigationStack OUTSIDE the content so Detail / the player still cover everything cleanly.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var tab: ShellTab = .home
    @State private var path = NavigationPath()
    @State private var showingProfiles = false
    @State private var showingSettings = false
    @FocusState private var focusedTab: ShellTab?

    var body: some View {
        VStack(spacing: 0) {
            // The bar lives ABOVE the NavigationStack, so `.searchable`'s field renders below it
            // (no overlap) — and it hides while a Detail/Player is pushed so those stay full-screen.
            if path.isEmpty {
                tabBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            NavigationStack(path: $path) {
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Browse/Search posters + the Search pill push ONE value type (stable link
                    // identity — see BrowseTile). The bare SearchHit/MediaItem destinations stay
                    // registered for the other pushers (Home rails, My Library, episode rows).
                    .navigationDestination(for: BrowseDestination.self) { dest in
                        switch dest {
                        case .detail(let item): detailDestination(item)
                        case .add(let hit): AddScreen(hit: hit)
                        case .search(let kind): SearchScreen(kind: kind)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasBackground())
        // Load the library once on appear (re-runs when `retry()` bumps `attempt`). This also
        // populates ownership so Browse can badge titles already in the library.
        .task(id: session.libraryStore?.attempt ?? -1) {
            await session.libraryStore?.load()
        }
        // Refresh Continue Watching when you land on Home, and when you return from a pushed
        // Detail/Player (the kept-alive Home tab won't re-run its own .task).
        .onChange(of: tab) { _, new in if new == .home { Task { await session.refreshHome() } } }
        .onChange(of: path.isEmpty) { _, empty in if empty { Task { await session.refreshHome() } } }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
                .environment(session)
                .onExitCommand { showingSettings = false }   // Menu closes Settings
        }
    }

    /// The library Detail for a pushed item (shared by the MediaItem and BrowseDestination routes).
    @ViewBuilder private func detailDestination(_ item: MediaItem) -> some View {
        if let details = session.detailsProvider {
            DetailView(item: item, details: details, watch: session.watchStore,
                       profileID: session.activeProfileID,
                       myList: session.myListStore,
                       ratings: session.ratingsProvider)
        }
    }

    /// The active profile avatar at the right of the top bar — tap to switch profiles.
    private var profileButton: some View {
        let p = session.activeProfiles?.activeProfile
        return Button { showingProfiles = true } label: {
            ProfileAvatarImage(token: p?.avatar ?? "", diameter: 56, colorTag: p?.colorTag ?? "gold")
        }
        .buttonStyle(.plain)
    }

    /// A focusable pill row. Moving focus across the pills only HIGHLIGHTS them; a Select press on a
    /// pill switches the page (commit-on-press — no accidental section changes when the remote glides).
    private var tabBar: some View {
        // Free pills using the exact same SeretPillStyle as the Browse segment pills — the focused
        // pill gets the gold fill + scale; a click on it commits the switch.
        HStack(spacing: 12) {
            ForEach(ShellTab.allCases) { t in
                Button { tab = t } label: { Label(t.title, systemImage: t.icon) }
                    .buttonStyle(SeretPillStyle(selected: tab == t))
                    .focused($focusedTab, equals: t)
            }
        }
        .padding(.top, 28).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            // Settings + profile sit off to the right — one step away, never in the primary row.
            HStack(spacing: 24) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(SeretPillStyle(selected: false))
                profileButton
            }
            .padding(.trailing, 50).padding(.top, 16)
        }
    }

    /// Pages stay alive across switches (instant, no rebuild → snappy). Home/Library are kept in the
    /// tree (hidden + disabled when inactive). Find exists only while active (it owns the Movies/Shows
    /// filter + browse); recreating it on entry keeps its search flow self-contained. The swap is
    /// INSTANT on purpose: crossfading the heavy poster grids read as a sluggish in-between.
    @ViewBuilder private var pages: some View {
        ZStack {
            keptAlive(tab == .home) { HomeScreen() }
            keptAlive(tab == .library) { MyLibraryScreen() }
            if tab == .find {
                FindScreen()
            }
        }
    }

    @ViewBuilder private func keptAlive<V: View>(_ visible: Bool, @ViewBuilder _ make: () -> V) -> some View {
        make()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }
}

/// The shell's tabs, in bar order.
private enum ShellTab: String, CaseIterable, Identifiable {
    case home, find, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .find: return "Find"
        case .library: return "My Library"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .find: return "magnifyingglass"
        case .library: return "rectangle.stack"
        }
    }
}

/// Shown only if a player can't be built while signed in (e.g. the SwiftData container failed).
/// Gives the user a way back instead of a soft-locked blank screen.
private struct PlaybackUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 54))
            Text("Unable to start playback.").font(.title2)
            Button("Back") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { dismiss() }
    }
}
