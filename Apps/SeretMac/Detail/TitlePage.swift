import DebridCore
import DebridUI
import SwiftUI

extension EnvironmentValues {
    /// Harness-only knob (`titletrailer`): the trailer normally waits a flat 4 s before it may
    /// autoplay — a screenshot can't wait that long, so the harness overrides it to near-zero.
    @Entry var previewTrailerDelay: Duration?
}

/// The full title page: hero (logo, credits, franchise, chips, Play/Resume/acquire) plus the
/// overview and, for a show, its season pills and episode grid.
struct TitlePage: View {
    let store: DetailStore
    /// A harness-injected acquirer wins; otherwise the page builds one once its store's imdbID is
    /// known — `TitleAcquirer` reads the store lazily, but building it needs the session on hand.
    @Environment(TitleAcquirer.self) private var injectedAcquirer: TitleAcquirer?
    @State private var ownAcquirer: TitleAcquirer?
    @State private var scrollOffset: CGFloat = 0

    /// Same seam as the acquirer — a harness-injected `TrailerModel` wins over the one the page
    /// builds and drives through the 4 s / autoplay-setting gate itself.
    @Environment(TrailerModel.self) private var injectedTrailer: TrailerModel?
    @State private var ownTrailer: TrailerModel?
    @State private var trailerAutoplayArmed = false

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset
    /// Harness-only: shortens the trailer's flat 4 s wait so a screenshot doesn't have to.
    @Environment(\.previewTrailerDelay) private var previewTrailerDelay: Duration?
    @FocusState private var ratingKeysFocused: Bool

    private var acquirer: TitleAcquirer? { injectedAcquirer ?? ownAcquirer }
    private var trailer: TrailerModel? { injectedTrailer ?? ownTrailer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(store: store, acquirer: acquirer, scrollOffset: scrollOffset,
                         trailer: trailer, autoplayArmed: trailerAutoplayArmed)
                content
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            scrollOffset = y
        }
        // Decision 11 — unmodified digits rate 1–10 with no text field focused; ⌘/⌥/⌃ pass
        // through untouched (`RatingKey.value` already refuses them), so ⌘1…⌘5 still switch
        // sections. Focused on appear so a push straight from search doesn't leave the field with
        // stray keystrokes, yet never re-steals focus later while the viewer is typing there.
        .focusable()
        .focusEffectDisabled()
        .focused($ratingKeysFocused)
        .onAppear { ratingKeysFocused = true }
        .onKeyPress(phases: .down) { press in
            guard store.canRate,
                  let value = RatingKey.value(for: press.characters, modifiers: press.modifiers)
            else { return .ignored }
            Task { await store.rate(RatingKey.next(current: store.userRating, pressed: value)) }
            return .handled
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
        .task(id: store.item.tmdbID) { await prepareTrailer() }
        .onChange(of: shell?.playbackEndedCount) { _, _ in Task { await store.reloadWatch() } }
    }

    /// The iPhone's `TrailerHero.prepare()` sequence: resolve, then wait out the rest of a flat
    /// 4 s from when the page opened (not 4 s after resolving), so a slow resolve doesn't also
    /// delay the autoplay past what the viewer already waited through. Runs on whichever model is
    /// in play — a harness-injected one exactly as much as one this page built itself.
    private func prepareTrailer() async {
        guard let tmdbID = store.item.tmdbID else { return }
        let model: TrailerModel
        if let injectedTrailer {
            model = injectedTrailer
        } else if let ownTrailer {
            model = ownTrailer
        } else if let session, let built = session.makeTrailerModel() {
            ownTrailer = built
            model = built
        } else {
            return
        }
        async let delay: Void = Task.sleep(for: previewTrailerDelay ?? .seconds(4))
        await model.prepare(tmdbID: tmdbID, kind: store.item.kind)
        try? await delay
        guard model.autoplayAllowed, !Task.isCancelled else { return }
        trailerAutoplayArmed = true
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            overviewAndRating
            if store.item.kind == .movie, showDownloadSection {
                MovieDownloadSection(store: store, acquirer: acquirer)
            }
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

    /// A film with nothing to play right now, or one already tracked in the download store —
    /// covers both "never requested" and "requested, still going / failed".
    private var showDownloadSection: Bool {
        store.bestSource == nil || acquirer?.status(.movie) != nil
    }

    /// Mockup 5's two-column row: the overview on the left, "YOUR RATING" + history on the right.
    private var overviewAndRating: some View {
        HStack(alignment: .top, spacing: 40) {
            overview
            Spacer(minLength: 0)
            YourRating(store: store)
        }
        .frame(maxWidth: 1020, alignment: .leading)
    }

    @ViewBuilder private var overview: some View {
        if let text = store.overview, !text.isEmpty {
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(maxWidth: 620, alignment: .leading)
        } else if store.richState == .loading {
            VStack(alignment: .leading, spacing: 8) {
                ShimmerView(cornerRadius: 4).frame(width: 460, height: 14)
                ShimmerView(cornerRadius: 4).frame(width: 340, height: 14)
            }
        }
    }
}
