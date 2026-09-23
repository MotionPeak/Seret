import DebridCore
import DebridUI
import SwiftUI

/// The basic title page: hero (Play/Resume/Start Over) plus the overview and, for a show, its
/// season pills and episode grid. Everything else (cast, franchise, ratings, versions…) is M3.
struct TitlePage: View {
    let store: DetailStore

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(store: store)
                content
            }
        }
        .scrollIndicators(.hidden)
        .task {
            await store.load()
            let source = store.item.kind == .movie ? store.bestSource : store.nextEpisode()?.source
            if let source { session?.prefetchPlayback(for: source) }
        }
        .task { await store.loadPreferredVersion() }
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
