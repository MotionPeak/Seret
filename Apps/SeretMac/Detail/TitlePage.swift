import DebridCore
import DebridUI
import SwiftUI

/// The full title page: hero (logo, credits, franchise, chips, Play/Resume/acquire) plus the
/// overview and, for a show, its season pills and episode grid.
struct TitlePage: View {
    let store: DetailStore
    /// A harness-injected acquirer wins; otherwise the page builds one once its store's imdbID is
    /// known — `TitleAcquirer` reads the store lazily, but building it needs the session on hand.
    @Environment(TitleAcquirer.self) private var injectedAcquirer: TitleAcquirer?
    @State private var ownAcquirer: TitleAcquirer?
    @State private var scrollOffset: CGFloat = 0

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    private var acquirer: TitleAcquirer? { injectedAcquirer ?? ownAcquirer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(store: store, acquirer: acquirer, scrollOffset: scrollOffset)
                content
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            scrollOffset = y
        }
        .task {
            await store.load()
            let source = store.item.kind == .movie ? store.bestSource : store.nextEpisode()?.source
            if let source { session?.prefetchPlayback(for: source) }
        }
        .task { await store.loadPreferredVersion() }
        .task { await store.loadMyList(contentKey: store.item.id) }
        .task(id: store.imdbID) {
            guard injectedAcquirer == nil, ownAcquirer == nil, let session else { return }
            ownAcquirer = session.makeTitleAcquirer(for: store)
        }
        .onChange(of: shell?.playbackEndedCount) { _, _ in Task { await store.reloadWatch() } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            overview
            if store.item.kind == .show {
                VStack(alignment: .leading, spacing: 16) {
                    Text("EPISODES")
                        .font(Theme.Typo.label())
                        .tracking(1.5)
                        .foregroundStyle(Theme.Palette.gold)
                    SeasonPills(store: store)
                    EpisodeGrid(store: store)
                }
            }
        }
        .padding(.leading, pageLeadingInset)
        .padding(.trailing, 28)
        .padding(.top, 22)
        .padding(.bottom, 40)
    }

    @ViewBuilder private var overview: some View {
        if let text = store.overview, !text.isEmpty {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(maxWidth: 760, alignment: .leading)
        } else if store.richState == .loading {
            VStack(alignment: .leading, spacing: 8) {
                ShimmerView(cornerRadius: 4).frame(width: 620, height: 14)
                ShimmerView(cornerRadius: 4).frame(width: 460, height: 14)
            }
        }
    }
}
