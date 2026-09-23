import DebridCore
import DebridUI
import SwiftUI

extension EnvironmentValues {
    /// Harness-only knob (`titletrailer`): the trailer normally waits a flat 4 s before it may
    /// autoplay — a screenshot can't wait that long, so the harness overrides it to near-zero.
    @Entry var previewTrailerDelay: Duration?
    /// Harness-only knob (`titlerails`): scrolls the page to the bottom shortly after it appears,
    /// so a screenshot can show the franchise/cast/more-like-this rails without a pointer to drag.
    @Entry var previewScrollToBottom: Bool = false
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
    /// Harness-only: scrolls to the rails so they can be screenshotted without a pointer.
    @Environment(\.previewScrollToBottom) private var previewScrollToBottom: Bool
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var ratingKeysFocused: Bool

    /// The version awaiting a delete confirmation (nil = no alert).
    @State private var pendingVersionRemoval: MediaSource?
    @State private var versionsSheet: VersionsSheetPresentation?
    @State private var magnetSheet: MagnetSheetPresentation?

    private var acquirer: TitleAcquirer? { injectedAcquirer ?? ownAcquirer }
    private var trailer: TrailerModel? { injectedTrailer ?? ownTrailer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(store: store, acquirer: acquirer, scrollOffset: scrollOffset,
                         trailer: trailer, autoplayArmed: trailerAutoplayArmed,
                         onFindOtherVersions: { openVersionsSheet() })
                content
                rails
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
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
        .task {
            guard previewScrollToBottom else { return }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(nil) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: shell?.playbackEndedCount) { _, _ in Task { await store.reloadWatch() } }
        // Decision 8 / the Wiring bullet: every "Add by Magnet…" control (⋯, the download section,
        // File ▸ …) bumps the same counter; only the page actually on top opens its sheet.
        .onChange(of: shell?.magnetRequest) { _, _ in
            guard shell?.titleOnTop?.id == store.item.id, magnetSheet == nil,
                  let session, let downloads = session.downloadStore, let target = magnetTarget
            else { return }
            magnetSheet = MagnetSheetPresentation(model: MagnetAddModel(target: target, downloads: downloads))
        }
        .sheet(item: $versionsSheet) { presented in
            VersionsSheet(model: presented.model, onPlay: { request in
                versionsSheet = nil
                shell?.present(request)
                shell?.showToast("Added to Real\u{2011}Debrid")
            }, onClose: { versionsSheet = nil })
            .frame(minWidth: 680, minHeight: 560)
        }
        .sheet(item: $magnetSheet) { presented in
            MagnetSheet(model: presented.model, title: store.item.title, onDone: {
                magnetSheet = nil
                shell?.showToast("Sent to Real\u{2011}Debrid \u{2014} progress shows on this page")
            })
            .frame(minWidth: 560, minHeight: 320)
        }
        .alert("Delete this version?", isPresented: Binding(
            get: { pendingVersionRemoval != nil },
            set: { if !$0 { pendingVersionRemoval = nil } }), presenting: pendingVersionRemoval) { source in
            Button("Delete", role: .destructive) { performVersionRemove(source) }
            Button("Cancel", role: .cancel) { pendingVersionRemoval = nil }
        } message: { source in
            Text(store.versions.count > 1
                 ? "\(source.versionSummary) is deleted from your Real\u{2011}Debrid account. Your other versions of \u{201C}\(store.item.title)\u{201D} stay."
                 : "\(source.versionSummary) is the only version you have, so \u{201C}\(store.item.title)\u{201D} leaves your library.")
        }
    }

    /// What Add by Magnet files under here: the film, or the selected season for a show.
    private var magnetTarget: MagnetAddModel.Target? {
        switch store.item.kind {
        case .movie: return DownloadTarget.movie(store.item)?.magnet
        case .show: return DownloadTarget.season(of: store.item, store.selectedSeason)?.magnet
        }
    }

    private func openVersionsSheet(target: AcquisitionStore.Target = .movie) {
        guard let session, let model = session.makeVersionsModel(for: store.item, target: target) else { return }
        versionsSheet = VersionsSheetPresentation(model: model)
    }

    /// Delete ONE version from Real-Debrid. The last one takes the whole title with it, so the
    /// page pops back if it is still the one showing; otherwise it stays open with that row gone —
    /// tvOS `DetailView.performVersionRemove`, moved here.
    private func performVersionRemove(_ source: MediaSource) {
        guard let library = session?.libraryStore else { return }
        pendingVersionRemoval = nil
        Task {
            switch await library.removeVersionReportingFailure(store.item, source: source) {
            case let .removed(wasLast):
                if wasLast {
                    shell?.popTitleIfShowing(store.item.id)
                } else {
                    await store.forgetVersion(source)
                }
            case let .failed(message):
                shell?.removalError = message
            }
        }
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
            if store.item.kind == .movie, !store.versions.isEmpty {
                VersionsSection(store: store, onFindOtherVersions: { openVersionsSheet() },
                               onRemoveVersion: { pendingVersionRemoval = $0 })
            }
            if store.item.kind == .movie, showDownloadSection {
                MovieDownloadSection(store: store, acquirer: acquirer)
            }
            if store.item.kind == .show {
                VStack(alignment: .leading, spacing: 16) {
                    Text("EPISODES")
                        .font(Theme.Typo.label())
                        .tracking(1.5)
                        .foregroundStyle(Theme.Palette.gold)
                    HStack(alignment: .center) {
                        SeasonPills(store: store)
                        Spacer(minLength: 20)
                        SeasonActions(store: store, acquirer: acquirer, onMagnet: { shell?.requestMagnet() })
                    }
                    EpisodeGrid(store: store, acquirer: acquirer, onFindOtherVersions: { season, number in
                        openVersionsSheet(target: .episode(season: season, number: number))
                    })
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

    /// Franchise (films only) · Cast · More Like This — one skeleton pair while the details call is
    /// still in flight (cast and similar are the two rails almost every title ends up with;
    /// franchise cannot be guessed, so loading never reserves room for a third), nothing at all once
    /// it lands with none of the three to show.
    @ViewBuilder private var rails: some View {
        if store.richState == .loading {
            VStack(alignment: .leading, spacing: 26) {
                RailSkeleton()
                RailSkeleton()
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        } else if hasAnyRail {
            VStack(alignment: .leading, spacing: 26) {
                if store.item.kind == .movie, let franchise = store.franchise {
                    FranchiseRail(store: store, franchise: franchise)
                }
                if !store.cast.isEmpty {
                    CastRail(store: store)
                }
                if !store.similar.isEmpty {
                    MoreLikeThisRail(store: store)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
    }

    private var hasAnyRail: Bool {
        (store.item.kind == .movie && store.franchise != nil) || !store.cast.isEmpty || !store.similar.isEmpty
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

/// Wraps a `VersionsModel` so `.sheet(item:)` can present it — a fresh `id` each time the sheet
/// opens, so re-opening after a close always builds a fresh model rather than reusing a stale one.
private struct VersionsSheetPresentation: Identifiable {
    let id = UUID()
    let model: VersionsModel
}

/// Wraps a `MagnetAddModel` so `.sheet(item:)` can present it.
private struct MagnetSheetPresentation: Identifiable {
    let id = UUID()
    let model: MagnetAddModel
}
