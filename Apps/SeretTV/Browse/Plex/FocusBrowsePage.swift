import DebridCore
import DebridUI
import SwiftUI

/// Layout constants shared by `FocusBrowsePage`, `PlexRail` and the pages built on them — one
/// place to tune the Plex frame. Not on `FocusBrowsePage` itself: a generic type cannot hold
/// stored statics, and a rail must read these without naming the page's `Rails` type.
enum FocusBrowseLayout {
    /// Where titles, the header text and the first tile start, measured inside the shell's content
    /// area — which starts at `SideMenu.footprint` (150) from the screen edge. 30 puts them at 180,
    /// ~50pt clear of the collapsed capsule's right edge (128): the mockup's 170, plus room for a
    /// focused poster's 1.08 lift.
    static let leadingInset: CGFloat = 30
    /// The fixed preview header, from the top of the safe area to the top of the rail area.
    static let headerHeight: CGFloat = 470
    /// Header text starts this far below the safe area — 60 + 50 = the mockup's 110.
    static let headerTopPadding: CGFloat = 50
    /// Room above and below each rail's tiles for the focus lift, ring and shadow.
    static let railVerticalPadding: CGFloat = 36
    /// Overlaps consecutive rails' paddings, so the rail pitch is the mockup's ~450pt and the next
    /// rail's title peeks in at the bottom of the screen. Exactly one padding: the rail above the
    /// focused one then ends flush with the top of the rail area, so no sliver of its tiles shows
    /// through the top fade. One padding still keeps a lifted tile clear of the next title.
    static let railSpacing: CGFloat = -36
    /// Empty space after the last rail, so it too can scroll up to the top of the rail area.
    static let bottomRunway: CGFloat = 160
    /// How long a subject whose art is not cached may hold its title slot empty, waiting for the
    /// logo, before it shows the title as text. The header's own fade covers most of it.
    static let logoBudget: Duration = .milliseconds(200)
    /// How long the backdrop waits for the art's (usually textless) backdrop before falling back
    /// to the tile's own — so a first view fades once to the right plate, not twice. Measured from
    /// the settle's start, so it includes the logo hold.
    static let backdropArtBudget: Duration = .milliseconds(700)
}

/// A Plex-style browse page: a fixed preview header describing the focused tile, over an
/// ultrablur backdrop of its art, above a vertical stack of `PlexRail`s.
///
/// - The header follows `preview.shown`, which the tiles drive through `FocusPreviewModel.focus`
///   (debounced, so gliding along a rail never re-renders the header or backdrop per tile). Its
///   text switches the moment the debounce settles; only the title slot may wait — briefly — for
///   a logo that is not cached yet (see `FocusBrowseLayout.logoBudget`).
/// - The backdrop is independent of the header: it changes when the new title's plate is ready.
/// - When focus enters a rail, the rail scrolls to the top of the rail area, so the focused row
///   always sits in the same place under the header — calm and predictable, like Plex. A row
///   inserted above it later (rails that arrive progressively) is followed by the same scroll.
/// - `initialFocus` names the tile (or button) that takes focus when the page first resolves
///   focus; mark it with `.plexFocusID(_:)`. Also the target tvOS re-homes to when the focused
///   view vanishes, which is what keeps a Try Again button focused through a reload.
/// - The page reads `TitleArtStore` results only: its `.task(id:)` asks the store to load the
///   shown subject's art (the store owns the fetch), and the body looks up the art for the
///   subject on screen — so an older title's art can never paint over a newer one.
struct FocusBrowsePage<Rails: View>: View {
    @Bindable var preview: FocusPreviewModel
    let art: TitleArtStore?
    var initialFocus: String?
    @ViewBuilder var rails: Rails

    static var leadingInset: CGFloat { FocusBrowseLayout.leadingInset }

    /// The subject whose title slot is being held for its logo, if any.
    @State private var holdingTitleFor: String?
    /// The title the last settle was for — a re-settle of the same title (its progress changed)
    /// must not blank a title slot that is already showing.
    @State private var lastSettledID: String?
    /// What the backdrop shows. Lags the header only while a title's art is on its way.
    @State private var backdropPath: String?
    /// The row focus is in, as reported by `plexBrowseRow(id:)`.
    @State private var focusedRow: String?
    /// When the page last scrolled a row to the top — re-alignment waits for that to finish.
    @State private var lastRowScroll = ContinuousClock.now
    /// The focused row's latest offset from the top of the rail area (see `FocusedRowOffsetKey`).
    @State private var focusedRowOffset: CGFloat?
    /// A re-alignment deferred until the page's own scroll has finished.
    @State private var pendingRealign: Task<Void, Never>?
    /// Whether any subject has been shown since the page appeared (or since it last had none). Not
    /// the same as "a backdrop is up": a title with no art shows the canvas, and the next title
    /// after it is not a first appearance.
    @State private var hasShownSubject = false
    @FocusState private var focusedID: String?

    init(preview: FocusPreviewModel, art: TitleArtStore?, initialFocus: String? = nil,
         @ViewBuilder rails: () -> Rails) {
        self.preview = preview
        self.art = art
        self.initialFocus = initialFocus
        self.rails = rails()
    }

    var body: some View {
        let subject = preview.shown
        VStack(alignment: .leading, spacing: 0) {
            FocusPreviewHeader(subject: subject, art: subject.flatMap(artFor),
                               holdTitle: subject != nil && holdingTitleFor == subject?.id)
                .padding(.top, FocusBrowseLayout.headerTopPadding)
                .padding(.leading, FocusBrowseLayout.leadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: FocusBrowseLayout.headerHeight, alignment: .top)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: FocusBrowseLayout.railSpacing) {
                        rails
                    }
                    .padding(.bottom, FocusBrowseLayout.bottomRunway)
                }
                // Rails scroll edge to edge (a tile scrolled left runs on under the side menu, as in
                // Plex) — but a rail leaving the top must dissolve, not be sliced against the
                // header. The fade band is the focused rail's own top padding, so it never touches
                // the focused rail's title.
                .scrollClipDisabled()
                .gridTopFade(FocusBrowseLayout.railVerticalPadding)
                .onChange(of: focusedRow) { _, row in
                    guard let row else { return }
                    lastRowScroll = .now
                    withAnimation(Theme.Anim.railScroll) { proxy.scrollTo(row, anchor: .top) }
                }
                // The focused row moved without a focus change — a row was inserted (or resized)
                // above it. Put it back at the top, once any scroll of our own has finished.
                .onPreferenceChange(FocusedRowOffsetKey.self) { offset in
                    focusedRowOffset = offset
                    realignFocusedRow(proxy)
                }
            }
            // Rails run to the bottom of the screen, so the next rail's title peeks in.
            .ignoresSafeArea(edges: .bottom)
        }
        .background { backdrop }
        .defaultFocus($focusedID, initialFocus)
        .environment(\.focusBrowseRowFocused, { focusedRow = $0 })
        .environment(\.focusBrowseFocusedRow, focusedRow)
        .environment(\.focusBrowseFocusID, $focusedID)
        // Keyed on the whole subject, so a change to it (new progress → "Xm left") re-settles.
        .task(id: subject) { await settle(subject) }
    }

    /// The railScroll animation plus a margin.
    private static var scrollSettle: Duration { .milliseconds(650) }

    /// The backdrop, full-bleed: out past the safe area AND past the shell's leading inset, so the
    /// art runs under the side menu as it does in Plex.
    private var backdrop: some View {
        GeometryReader { geo in
            let lead = max(0, geo.frame(in: .global).minX)
            UltrablurBackdrop(backdropPath: backdropPath)
                .frame(width: geo.size.width + lead, height: geo.size.height)
                .offset(x: -lead)
        }
        .ignoresSafeArea()
    }

    /// Puts the focused row back at the top when something moved it — or, while the page's own
    /// scroll is still running, re-checks once that scroll is over. Never drops the request: rails
    /// streaming in right after the initial-focus scroll are exactly the ones that must be caught.
    private func realignFocusedRow(_ proxy: ScrollViewProxy) {
        guard let offset = focusedRowOffset, abs(offset) > 1, let row = focusedRow else { return }
        let since = ContinuousClock.now - lastRowScroll
        if since >= Self.scrollSettle {
            lastRowScroll = .now
            withAnimation(Theme.Anim.railScroll) { proxy.scrollTo(row, anchor: .top) }
        } else if pendingRealign == nil {
            let remaining = Self.scrollSettle - since
            pendingRealign = Task { @MainActor in
                try? await Task.sleep(for: remaining)
                pendingRealign = nil
                realignFocusedRow(proxy)       // reads the LATEST offset, not the one that queued it
            }
        }
    }

    private func artFor(_ subject: PreviewSubject) -> TitleArt? {
        guard let art, let id = subject.tmdbID else { return nil }
        return art.art(for: subject.kind, tmdbID: id)
    }

    /// Brings the title slot and the backdrop to `subject`. The header text has already switched
    /// (the body reads `preview.shown`); this only decides how long the title slot holds for a
    /// logo and which backdrop to show. A newer subject cancels it, so only the latest lands.
    private func settle(_ subject: PreviewSubject?) async {
        guard let subject else {
            holdingTitleFor = nil
            backdropPath = nil
            lastSettledID = nil
            hasShownSubject = false
            return
        }
        let start = ContinuousClock.now
        let sameTitle = subject.id == lastSettledID
        lastSettledID = subject.id
        // The very first subject (nothing on screen yet) draws at once: its title as text, its
        // tile's own backdrop. A better plate or the logo cross-fade in when they arrive.
        let first = !hasShownSubject
        hasShownSubject = true
        guard let store = art, let tmdbID = subject.tmdbID, artFor(subject) == nil else {
            // Art cached (logo and backdrop known now), or nothing to fetch.
            holdingTitleFor = nil
            backdropPath = artFor(subject)?.backdropPath ?? subject.backdropPath
            return
        }
        if first { backdropPath = subject.backdropPath }

        // Store-owned loads: these run to completion even if this settle is superseded.
        let kind = subject.kind
        let artLoad = Task { await store.load(kind, tmdbID: tmdbID) }
        let logoLoad = Task {
            guard let url = TMDBClient.imageURL(path: await artLoad.value?.logoPath, size: "w500")
            else { return }
            _ = await ImageMemoryCache.load(url)
        }

        if !first && !sameTitle {
            holdingTitleFor = subject.id
            await FocusSettle.wait(for: logoLoad, upTo: FocusBrowseLayout.logoBudget)
            guard !Task.isCancelled else { return }
        }
        holdingTitleFor = nil

        // Both budgets run from the settle's start: the backdrop waits at most `backdropArtBudget`
        // in all, not the logo hold plus that.
        let backdropBudget = FocusBrowseLayout.backdropArtBudget - (ContinuousClock.now - start)
        await FocusSettle.wait(for: artLoad, upTo: max(.zero, backdropBudget))
        guard !Task.isCancelled else { return }
        backdropPath = artFor(subject)?.backdropPath ?? subject.backdropPath
        guard artFor(subject) == nil else { return }

        // The art is late: once it lands, move to its backdrop if it names a different one.
        // (Cancellable wait, so a superseded settle lets go at once.)
        await FocusSettle.wait(for: artLoad, upTo: .seconds(30))
        guard !Task.isCancelled else { return }
        backdropPath = artFor(subject)?.backdropPath ?? subject.backdropPath
    }
}

/// Waiting on a store-owned load without owning it.
enum FocusSettle {
    /// Returns when `task` finishes, `limit` passes, or the caller is cancelled — whichever is
    /// first. `task` itself is never cancelled: it belongs to whoever started it, and a load
    /// abandoned here should still land in its cache for the next look.
    static func wait(for task: Task<Void, Never>, upTo limit: Duration) async {
        let once = ResumeOnce()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                once.set(continuation)
                Task { await task.value; once.resume() }
                once.setTimer(Task { try? await Task.sleep(for: limit); once.resume() })
            }
        } onCancel: {
            once.resume()
        }
    }

    static func wait<T: Sendable>(for task: Task<T, Never>, upTo limit: Duration) async {
        await wait(for: Task { _ = await task.value }, upTo: limit)
    }

    /// Resumes a continuation exactly once, whichever caller gets there first — including a
    /// cancellation that arrives before the continuation does.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var timer: Task<Void, Never>?
        private var resumed = false

        /// The budget's sleeper, cancelled as soon as anything resumes so it does not linger.
        func setTimer(_ timer: Task<Void, Never>) {
            lock.lock()
            if resumed {
                lock.unlock()
                timer.cancel()
                return
            }
            self.timer = timer
            lock.unlock()
        }

        func set(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if resumed {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func resume() {
            lock.lock()
            resumed = true
            let continuation = self.continuation
            let timer = self.timer
            self.continuation = nil
            self.timer = nil
            lock.unlock()
            timer?.cancel()
            continuation?.resume()
        }
    }
}

/// The focused row's top, relative to the top of the rail area. Zero once it is in place.
struct FocusedRowOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}
