import DebridCore
import DebridUI
import SwiftUI

/// Home tab: a featured hero (most recent Continue item) + Continue Watching and
/// Recently Added rails, composed on `session.home`. Taps open Detail full-screen.
struct HomeScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(AppRouter.self) private var router
    @State private var showingProfiles = false
    @State private var showingSettings = false

    private var isRegular: Bool { hSize == .regular }
    private var posterW: CGFloat { isRegular ? 150 : 112 }
    private var landW: CGFloat { isRegular ? 280 : 178 }
    private var heroH: CGFloat { isRegular ? 380 : 250 }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                content
            }
            .navigationTitle("Home")
            .toolbar {
                // iPhone: profile avatar + Settings gear in the nav bar (iPad uses the sidebar).
                if !isRegular {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape").tint(Theme.Palette.textPrimary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingProfiles = true } label: {
                            ProfileAvatarImage(token: session.activeProfiles?.activeProfile?.avatar ?? "",
                                               diameter: 32,
                                               colorTag: session.activeProfiles?.activeProfile?.colorTag ?? "gold")
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingProfiles) {
            WhoIsWatchingScreen(onPicked: { showingProfiles = false }).environment(session)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }.tint(Theme.Palette.gold)
                        }
                    }
            }
        }
        .task {
            await session.libraryStore?.load()
            await rebuild()
        }
        .onChange(of: session.libraryStore?.movies) { _, _ in Task { await rebuild() } }
        .onChange(of: session.libraryStore?.shows) { _, _ in Task { await rebuild() } }
        // The active profile resolves asynchronously after sign-in; rebuild once it's known.
        .onChange(of: session.activeProfileID) { _, _ in Task { await rebuild() } }
        // Re-enter the Home tab (e.g. after watching something) → refresh Continue Watching.
        .onAppear { Task { await rebuild() } }
        // The player is presented above the shell, so dismissing it doesn't fire onAppear here —
        // rebuild when it closes so the resume position / Continue Watching order update.
        .onChange(of: router.playback == nil) { _, closed in if closed { Task { await rebuild() } } }
    }

    @ViewBuilder private var content: some View {
        if let home = session.home {
            if home.continueWatching.isEmpty && home.recentlyAdded.isEmpty {
                if session.libraryStore?.state == .loading { loading } else { empty }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xxl) {
                        hero(home)
                        if !home.continueWatching.isEmpty {
                            Rail(title: "Continue Watching") {
                                ForEach(home.continueWatching) { hi in
                                    Button { resume(hi) } label: {
                                        LandscapeProgressCard(title: hi.item.title, subtitle: hi.subtitle,
                                                              imageURL: backdropURL(hi.item),
                                                              fraction: hi.fraction, width: landW)
                                    }.pressable()
                                }
                            }
                        }
                        if !home.recentlyAdded.isEmpty {
                            Rail(title: "Recently Added") {
                                ForEach(home.recentlyAdded) { item in
                                    Button { router.detail = item } label: {
                                        PosterCard(title: item.title,
                                                   posterURL: posterURL(item), width: posterW)
                                    }.pressable()
                                }
                            }
                        }
                    }
                    .padding(.vertical, Theme.Space.lg)
                }
            }
        } else {
            ProgressView().tint(Theme.Palette.gold)
        }
    }

    @ViewBuilder private func hero(_ home: HomeStore) -> some View {
        if let f = home.featured {
            HeroBackdrop(imageURL: backdropURL(f.item), height: heroH) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(f.subtitle.isEmpty ? "Continue Watching" : "Continue · \(f.subtitle)")
                        .font(Theme.Typo.label()).tracking(1.5).foregroundStyle(Theme.Palette.gold)
                    Text(f.item.title).font(Theme.Typo.titleXL())
                        .foregroundStyle(Theme.Palette.textPrimary).lineLimit(2)
                    // The pill resumes playback directly; tapping the hero art (below) opens Detail.
                    Button { resume(f) } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Resume") }
                            .font(Theme.Typo.headline()).foregroundStyle(Color(hex: 0x1A1400))
                            .padding(.vertical, 9).padding(.horizontal, Theme.Space.xl)
                            .background(Theme.Palette.goldGradient, in: Capsule())
                            .goldGlow(12, opacity: 0.4).padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { router.detail = f.item }
            .padding(.horizontal, Theme.Space.lg)
        }
    }

    /// Resume playback straight from a rail. Falls back to the Detail page only if the file can't be
    /// resolved (e.g. the version was removed since it was last watched).
    private func resume(_ hi: HomeItem) {
        if let request = hi.playbackRequest() {
            router.playback = PlaybackPresentation(request: request)
        } else {
            router.detail = hi.item
        }
    }

    private var loading: some View {
        VStack(spacing: Theme.Space.lg) {
            ShimmerView().frame(height: heroH).padding(.horizontal, Theme.Space.lg)
            ShimmerView().frame(height: 120).padding(.horizontal, Theme.Space.lg)
        }.padding(.top, Theme.Space.lg).frame(maxHeight: .infinity, alignment: .top)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.md) {
            SeretMark(glow: false).frame(width: 54).opacity(0.5)
            Text("Nothing here yet").font(Theme.Typo.headline()).foregroundStyle(Theme.Palette.textSecondary)
            Text("Play something and it'll show up here.").font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textTertiary)
        }.frame(maxWidth: .infinity).padding(.top, 100)
    }

    private func rebuild() async {
        guard let library = session.libraryStore, let home = session.home else { return }
        await home.rebuild(movies: library.movies, shows: library.shows)
        // Warm the rail images in the background so cards render filled instead of popping in
        // one by one as they scroll into view.
        var urls: [URL] = []
        if let f = home.featured, let u = backdropURL(f.item) { urls.append(u) }
        urls += home.continueWatching.compactMap { backdropURL($0.item) }
        urls += home.recentlyAdded.compactMap { posterURL($0) }
        ImageMemoryCache.prefetch(urls)
    }

    private func posterURL(_ i: MediaItem) -> URL? { TMDBClient.imageURL(path: i.posterPath, size: "w500") }
    private func backdropURL(_ i: MediaItem) -> URL? {
        TMDBClient.imageURL(path: i.backdropPath ?? i.posterPath, size: "w780")
    }
}
