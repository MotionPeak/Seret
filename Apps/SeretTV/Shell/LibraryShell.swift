import DebridCore
import DebridUI
import SwiftUI

/// The signed-in root: a custom Gold Glass top tab bar (Home · Movies · TV · My Library ·
/// Settings) over the switched content. The tab bar switches ON FOCUS (move-to-switch, no press
/// needed) — same proven pattern as the in-player SettingsPanel. One root NavigationStack OUTSIDE
/// the content so Detail / the player still cover everything cleanly.
struct LibraryShell: View {
    @Environment(AppSession.self) private var session
    @State private var tab: ShellTab = .home
    @State private var path = NavigationPath()
    @State private var showingProfiles = false
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
                    .navigationDestination(for: SearchHit.self) { hit in
                        AddScreen(hit: hit)
                    }
                    .navigationDestination(for: MediaItem.self) { item in
                        if let details = session.detailsProvider {
                            DetailView(item: item, details: details, watch: session.watchStore,
                                       profileID: session.activeProfileID,
                                       myList: session.myListStore,
                                       ratings: session.ratingsProvider)
                        }
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
    }

    /// The active profile avatar at the right of the top bar — tap to switch profiles.
    private var profileButton: some View {
        let p = session.activeProfiles?.activeProfile
        return Button { showingProfiles = true } label: {
            ZStack {
                Circle().fill(Theme.Palette.color(for: p?.colorTag ?? "gold")).frame(width: 56, height: 56)
                Text((p?.avatar.isEmpty == false ? p!.avatar : ProfileAvatars.fallback)).font(.system(size: 30))
            }
        }
        .buttonStyle(.card)
    }

    /// A focusable pill row. Moving focus across the pills switches the page live (onChange),
    /// so you never have to click a tab — exactly what the SettingsPanel tab bar does.
    private var tabBar: some View {
        // Free pills using the exact same SeretPillStyle as the Browse segment pills — switch on
        // focus (no press), with the same subtle gold fill + scale animation.
        HStack(spacing: 12) {
            ForEach(ShellTab.allCases) { t in
                Button { tab = t } label: { Label(t.title, systemImage: t.icon) }
                    .buttonStyle(SeretPillStyle(selected: tab == t))
                    .focused($focusedTab, equals: t)
            }
        }
        .padding(.top, 28).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { profileButton.padding(.trailing, 50).padding(.top, 16) }
        .onChange(of: focusedTab) { _, new in
            // Instant swap — no crossfade. Animating a tab change cross-dissolved the whole page
            // (heavy poster grids included), which read as a sluggish "in-between" transition.
            // The native tvOS feel is an immediate switch; the pages are kept alive so it's free.
            if let new { tab = new }
        }
    }

    /// Pages stay alive across switches (instant, no rebuild → snappy). Home/Library/Settings are
    /// kept in the tree (hidden + disabled when inactive). Movies/TV share ONE BrowseScreen whose
    /// `kind` follows the tab (so Movies↔TV is an instant content swap, not a rebuild) — it only
    /// exists while active so its `.searchable` bar never leaks onto the other tabs.
    @ViewBuilder private var pages: some View {
        ZStack {
            keptAlive(tab == .home) { HomeScreen() }
            keptAlive(tab == .library) { MyLibraryScreen() }
            keptAlive(tab == .settings) { SettingsView() }
            if tab == .movies || tab == .tv {
                BrowseScreen(kind: tab == .tv ? .show : .movie)
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
    case home, movies, tv, library, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .tv: return "TV"
        case .library: return "My Library"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .tv: return "tv"
        case .library: return "rectangle.stack"
        case .settings: return "gearshape"
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
