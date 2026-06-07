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
    @FocusState private var focusedTab: ShellTab?

    var body: some View {
        VStack(spacing: 0) {
            // The bar lives ABOVE the NavigationStack, so `.searchable`'s field renders below it
            // (no overlap) — and it hides while a Detail/Player is pushed so those stay full-screen.
            if path.isEmpty {
                tabBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            NavigationStack(path: $path) {
                content
                    .id(tab)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationDestination(for: SearchHit.self) { hit in
                        AddScreen(hit: hit)
                    }
                    .navigationDestination(for: MediaItem.self) { item in
                        if let details = session.detailsProvider {
                            DetailView(item: item, details: details, watch: session.watchStore)
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
    }

    /// A focusable pill row. Moving focus across the pills switches the page live (onChange),
    /// so you never have to click a tab — exactly what the SettingsPanel tab bar does.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(ShellTab.allCases) { t in
                ShellTabChip(tab: t, selected: tab == t)
                    .focusable()
                    .focused($focusedTab, equals: t)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 24).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .onChange(of: focusedTab) { _, new in
            // Quick crossfade — snappy but still animated (0.28 felt laggy on-device).
            if let new { withAnimation(.easeOut(duration: 0.14)) { tab = new } }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: HomeScreen()
        case .movies: BrowseScreen(kind: .movie)
        case .tv: BrowseScreen(kind: .show)
        case .library: MyLibraryScreen()
        case .settings: SettingsView()
        }
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

/// One tab pill: focused → solid gold + black; selected (current page) → faint gold + gold text;
/// otherwise transparent + secondary text. Reads `\.isFocused` so the highlight is uniform.
private struct ShellTabChip: View {
    let tab: ShellTab
    let selected: Bool
    @Environment(\.isFocused) private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.icon)
            Text(tab.title)
        }
        .font(.headline)
        .foregroundStyle(focused ? .black : (selected ? Theme.Palette.gold : Theme.Palette.textSecondary))
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(fill, in: Capsule())
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
    private var fill: AnyShapeStyle {
        if focused { return AnyShapeStyle(Theme.Palette.goldGradient) }
        if selected { return AnyShapeStyle(Theme.Palette.gold.opacity(0.16)) }
        return AnyShapeStyle(Color.clear)
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
