import DebridCore
import DebridUI
import SwiftUI

/// The signed-in window: full-bleed page content under the floating sidebar. The page's leading edge
/// follows the sidebar's width on the same spring, so collapsing glides the whole page. Each section
/// is its own `NavigationStack`, and pages read their leading clearance from the environment instead
/// of the shell padding them — so later full-bleed art can run under the sidebar.
///
/// Playback is an overlay layer, not a cover or a second window: the section content underneath
/// stays mounted (opacity 0, no hit testing, hidden from accessibility) so the title page keeps its
/// scroll position, and `.id(presentation.id)` guarantees one `PlayerHost` per presentation.
struct MainShell: View {
    /// Sections opened at least once — kept alive so returning to one is instant.
    @State private var visitedSections: Set<SidebarSection> = []
    @Bindable var model: ShellModel
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Harness-only (`-uiPreview flight`/`flightback`): pins the flyer at an exact progress.
    @Environment(\.previewFlightProgressOverride) private var previewFlightProgressOverride: Double?

    // A harness-injected instance wins; otherwise this shell builds one once and re-injects it, so
    // every page underneath reads the same object instead of each rebuilding its own (Decision 6).
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var injectedMarks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var injectedWatchlist: WatchlistMarks?
    @Environment(\.searchStore) private var injectedSearchStore: SearchStore?
    @State private var ownMarks: TileWatchMarks?
    @State private var ownWatchlist: WatchlistMarks?
    // Per-window, never shared through the session (Decision 4) — two windows must not overwrite
    // each other's search results.
    @State private var ownSearchStore: SearchStore?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var watchlist: WatchlistMarks? { injectedWatchlist ?? ownWatchlist }
    private var searchStore: SearchStore? { injectedSearchStore ?? ownSearchStore }

    var body: some View {
        core.shellConfirmationsAndAlerts(model: model, confirmRemoval: confirmRemoval)
    }

    // Split out of `body`: one big expression mixing the ZStack, a dozen modifiers and three
    // `.alert`s was too much for the type checker to solve in reasonable time.
    /// Playback or the trailer overlay hides the section content underneath — the same reason
    /// playback does (the title page keeps its scroll position mounted at opacity 0).
    private var anOverlayIsUp: Bool { model.playback != nil || model.trailer != nil }

    private var core: some View {
        ZStack {
            shellContent
                .opacity(anOverlayIsUp ? 0 : 1)
                .allowsHitTesting(!anOverlayIsUp)
                .accessibilityHidden(anOverlayIsUp)
            if !anOverlayIsUp {
                ShellToastView(model: model)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if let trailer = model.trailer {
                TrailerOverlay(presentation: trailer, onClose: { model.closeTrailer() })
                    .id(trailer.id)
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let playback = model.playback, let session {
                PlayerHost(request: playback.request, app: session, onExit: { model.endPlayback() },
                           onTornDown: { model.playerDidTearDown() })
                    .id(playback.id)          // a new presentation is a new host
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(Theme.Motion.fade, value: model.playback?.id)
        .animation(Theme.Motion.fade, value: model.trailer?.id)
        .environment(\.pageLeadingInset, SidebarMetrics.contentLeading(collapsed: model.isSidebarCollapsed))
        .environment(model)
        .environment(injectedMarks ?? ownMarks ?? .placeholder)
        .environment(watchlist ?? .placeholder)
        .environment(\.searchStore, searchStore)
        .background(TrafficLightsPlacement(origin: SidebarMetrics.trafficLightsOrigin))
        .animation(Theme.Motion.standard, value: model.isSidebarCollapsed)
        .animation(Theme.Motion.fade, value: model.selection)
        .animation(Theme.Motion.fade, value: model.isSearching)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 650)
        .focusedSceneValue(\.shellModel, model)
        // Every poster tile's and the title hero's own frame (Decision 10) is reported in THIS
        // space, so a flight's `from`/`to` are always comparable no matter which page they came
        // from.
        .coordinateSpace(.named(ShellSpace.window))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.windowSize = $0 }
        .onChange(of: reduceMotion, initial: true) { _, new in model.reduceMotion = new }
        // The library loads here, not only on My Library — Home and Browse need ownership and
        // watch state without a visit there, and the splash covers this first load (Decision 7).
        .task(id: library?.attempt ?? -1) { await library?.load() }
        #if DEBUG
        .task {
            // `-scrollBench <section>`: open that section, let it load, then measure scrolling.
            guard let name = ScrollBench.requestedSection(),
                  let section = SidebarSection.allCases.first(where: { "\($0)" == name }) else { return }
            model.select(section)
            ScrollBench.run(after: UserDefaults.standard.object(forKey: "scrollBenchDelay") as? Double ?? Double(UserDefaults.standard.string(forKey: "scrollBenchDelay") ?? "") ?? 9)
        }
        #endif
        .task {
            guard let session else { return }
            if injectedMarks == nil, ownMarks == nil { ownMarks = session.makeTileWatchMarks() }
            if injectedWatchlist == nil, ownWatchlist == nil { ownWatchlist = session.makeWatchlistMarks() }
            if injectedSearchStore == nil, ownSearchStore == nil {
                ownSearchStore = SearchStore(search: TMDBSearchService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))
            }
            await watchlist?.load()
        }
        .onChange(of: watchlist?.lastOutcome?.event) { _, _ in
            if let outcome = watchlist?.lastOutcome {
                model.showToast(outcome.message, isFailure: outcome.isFailure)
            }
        }
    }

    private var shellContent: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            // Every section visited so far stays alive underneath; switching only reveals one.
            // Rebuilding the stack per switch (`.id(selection)`) threw away each page's loaded
            // state — every visit re-fetched and re-laid-out from scratch, and lost its scroll.
            ForEach(SidebarSection.allCases.filter { visitedSections.contains($0) || $0 == model.selection }) { section in
                let isShown = section == model.selection && !model.isSearching
                SectionStack(section: section, model: model)
                    .environment(\.isPageShown, isShown)
                    .opacity(isShown ? 1 : 0)
                    .allowsHitTesting(isShown)
                    .accessibilityHidden(!isShown)
            }
            .animation(Theme.Motion.fade, value: model.selection)
            .onChange(of: model.selection, initial: true) { _, section in visitedSections.insert(section) }
            // Search: its own stack over the section, built fresh each time Search opens.
            if model.isSearching {
                SearchStack(model: model)
                    .transition(.opacity)
            }
            if let flight = model.flight {
                HeroFlightDriver(flight: flight, progressOverride: previewFlightProgressOverride,
                                 onLand: { model.landFlight($0) })
                    .id(flight.id)
            }
            FloatingSidebar(model: model)
            BackForwardCapsule(model: model)
            SearchField(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
                .padding(.top, 14)
            if let surprise = model.surprise {
                SurpriseReel(spin: surprise.spin,
                             onWatch: { entry in
                                 model.surprise = nil
                                 if let item = MediaItem.watchlistMovie(entry) { model.open(.title(item)) }
                             },
                             onSpinAgain: {
                                 if let next = surprise.respin() { model.surprise?.spin = next }
                             },
                             onClose: { model.surprise = nil })
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(Theme.Motion.fade, value: model.surprise?.id)
    }

    private func confirmRemoval(_ item: MediaItem) {
        model.pendingRemoval = nil
        Task {
            if let message = await library?.removeReportingFailure(item) {
                model.removalError = message
            } else {
                // Removed clean — if the title page for it is what's on top, there is nothing
                // left there to show.
                model.popTitleIfShowing(item.id)
            }
        }
    }
}

/// The removal confirm + "Couldn't Remove" + "Couldn't Play" alerts, hosted once here so any
/// poster's menu (Task 3) and `MyLibraryScreen`'s Play both just set state on `ShellModel`.
private extension View {
    func shellConfirmationsAndAlerts(model: ShellModel, confirmRemoval: @escaping (MediaItem) -> Void) -> some View {
        self
            .alert("Remove \u{201C}\(model.pendingRemoval?.title ?? "")\u{201D}?",
                   isPresented: Binding(get: { model.pendingRemoval != nil },
                                        set: { if !$0 { model.pendingRemoval = nil } }),
                   presenting: model.pendingRemoval) { item in
                Button("Remove", role: .destructive) { confirmRemoval(item) }
                Button("Cancel", role: .cancel) { model.pendingRemoval = nil }
            } message: { _ in
                Text("This deletes it from your Real\u{2011}Debrid account.")
            }
            .alert("Couldn\u{2019}t Remove",
                   isPresented: Binding(get: { model.removalError != nil },
                                        set: { if !$0 { model.removalError = nil } })) {
                Button("OK") { model.removalError = nil }
            } message: {
                Text(model.removalError ?? "")
            }
            .alert("Couldn\u{2019}t Play",
                   isPresented: Binding(get: { model.couldNotPlay != nil },
                                        set: { if !$0 { model.couldNotPlay = nil } })) {
                Button("OK") { model.couldNotPlay = nil }
            } message: {
                Text("Nothing playable is in your library for \u{201C}\(model.couldNotPlay?.title ?? "")\u{201D}.")
            }
    }
}
