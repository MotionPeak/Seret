import SwiftUI
import DebridUI
import DebridCore

/// What still takes SwiftUI focus inside the player. At rest NOTHING does — `PlayerInputSurface`
/// owns the remote, and no focusable sibling exists beside it, which is what lets touch-scrub and
/// directional clicks coexist. The control row, the settings sheet, the episode strip and the
/// rating stars are focusable, and each is mounted only while it is open.
enum PlayerFocus: Hashable {
    /// One case PER STAR of the post-credits rating row. Binding all ten to a single value let the
    /// focus engine pick whichever it liked — it took the LAST, so the row opened aimed at 10/10
    /// and one press would have filed that. Caught by screenshotting the `-uiPreview` harness.
    case rating(Int)
}

struct PlayerView: View {
    @State private var model: PlayerModel
    /// Nil only in the DEBUG harness, which draws a still in place of the picture.
    @State private var engine: VLCKitVideoPlayerEngine?
    /// The row of Subtitles / Audio / Speed / Episodes buttons Down opens under the bar.
    @State private var showControls = false
    /// The right-hand settings sheet, opened from the control row at `settingsSection`.
    @State private var showSettings = false
    @State private var settingsSection: SettingsSection = .subtitles
    /// The control row's button that opened the sheet: Menu on the sheet goes back to the row,
    /// with focus on that button. Nil when the sheet was not opened from the row.
    @State private var sheetOpenedFrom: PlayerControl?
    @State private var showEpisodes = false
    @State private var showSubtitleBrowser = false
    @State private var showManualSync = false
    /// The playhead when the current scrub gesture started — scrub displacement is relative to it.
    @State private var scrubOrigin: Double = 0
    /// Arrow nudges applied during the current scrub, folded into the origin so the next pan
    /// movement (which recomputes the target absolutely) does not discard them.
    @State private var scrubNudge: Double = 0
    @FocusState private var focus: PlayerFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The viewer pressed Up to answer the Letterboxd rating prompt. See `isRating`.
    @State private var ratingEngaged = false
    let backdropURL: URL?
    let pushSignal: LetterboxdPushSignal?
    let filmRating: FinishedFilmRating?
    /// DEBUG harness only: a still drawn where the picture would be.
    private var previewFrame: URL?

    init(model: PlayerModel, engine: VLCKitVideoPlayerEngine, backdropURL: URL?,
         pushSignal: LetterboxdPushSignal? = nil, filmRating: FinishedFilmRating? = nil) {
        _model = State(initialValue: model)
        _engine = State(initialValue: engine)
        self.backdropURL = backdropURL
        self.pushSignal = pushSignal
        self.filmRating = filmRating
    }

    #if DEBUG
    /// What the `-uiPreview` harness opens the real player on.
    enum PreviewOverlay { case none, controls, sheet(SettingsSection), subtitleBrowser }

    /// The real player — input surface, routing and all — over a still instead of libvlc, opened
    /// on an overlay, so the chrome can be screenshot-verified with no stream and no remote.
    init(previewModel model: PlayerModel, frame: URL?, opening overlay: PreviewOverlay) {
        _model = State(initialValue: model)
        _engine = State(initialValue: nil)
        backdropURL = nil
        pushSignal = nil
        filmRating = nil
        previewFrame = frame
        switch overlay {
        case .none: break
        case .controls: _showControls = State(initialValue: true)
        case .sheet(let section):
            _showSettings = State(initialValue: true)
            _settingsSection = State(initialValue: section)
            _sheetOpenedFrom = State(initialValue: section.control)
        case .subtitleBrowser: _showSubtitleBrowser = State(initialValue: true)
        }
    }
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()                      // black backing for the open transition
            if let engine {
                VideoSurface(videoView: engine.videoView).ignoresSafeArea()
            } else if let previewFrame {
                RemoteImage(url: previewFrame, contentMode: .fill) { _ in Color.black }
                    .ignoresSafeArea()
            }

            // The interaction layer is ALWAYS mounted. It used to be the `else` branch of the
            // loading check, so while "Buffering…" showed there was no input surface, no bar and
            // no Back affordance at all — and `.defaultFocus(.stage)` pointed at a view that did
            // not exist. Swapping the focused view's identity mid-playback is also the exact
            // anti-pattern that cost this app its Browse-tile focus (see CLAUDE.md).
            PlayerInputSurface(
                isActive: inputSurfaceActive,
                // Click pauses AND arms scrubbing; a swipe while playing never seeks.
                scrubEnabled: model.phase == .paused,
                onTouchDown: { model.revealScrubBar() },
                onTouchUp: {},
                // The origin is captured HERE, not from an `.onChange(of: model.isScrubbing)`.
                // The pan handler calls `onScrubBegan` and `onScrubMoved` in the same turn, and
                // `.onChange` does not run until SwiftUI's next update — so the first movement of
                // every scrub was measured from the PREVIOUS gesture's origin (or from 0 on the
                // first one). A quick flick past the threshold and a lift committed the seek to
                // that wrong time.
                onScrubBegan: { scrubOrigin = model.position; scrubNudge = 0; model.beginScrub() },
                onScrubMoved: { displacement in
                    let target = scrubOrigin + scrubNudge
                        + ScrubGain.seconds(forDisplacement: displacement, duration: model.duration)
                    model.updateScrub(by: target - model.scrubTarget)
                },
                onScrubEnded: { model.commitScrub() },
                onScrubCancelled: { model.cancelScrub() },
                onSkip: { delta in
                    // An arrow nudge mid-scrub has to move the ORIGIN, not just the target: the
                    // next pan movement recomputes the target absolutely from the origin, which
                    // silently threw the nudge away.
                    if model.isScrubbing { scrubNudge += delta; model.updateScrub(by: delta) }
                    else { model.skip(delta); model.revealScrubBar() }
                },
                onSelect: { model.togglePlayPause(); model.revealScrubBar() },
                onPlayPause: { model.togglePlayPause() },
                onUp: { openEpisodesOrRevealBar() },
                onDown: { openControlsOrCloseStrip() },
                onScanBegan: { direction in model.beginScan(direction: direction) },
                onScanEnded: { model.endScan() }
            )
            .ignoresSafeArea()

            // Paused, with nothing else up: a quiet glyph in the middle of the frame says so.
            if showsBigState {
                PausedGlyph()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .allowsHitTesting(false)
            }

            if topBarShown {
                PlayerTopBar(title: model.titleLines.title, subtitle: model.titleLines.subtitle,
                             showsClock: !showSettings)
                    .transition(.opacity)
            }

            // One bottom-anchored column: the scrub bar on top, the control row or the episode
            // strip beneath. Stacking them means the bar AUTOMATICALLY rides up as either opens.
            PlayerBottomBar(model: model, barShown: barShown, showEpisodes: $showEpisodes,
                            showControls: showControls, showSettings: showSettings,
                            showsHint: !model.upNextVisible,
                            controls: controls,
                            controlsFocus: sheetOpenedFrom,
                            onChoose: choose, onCloseControls: { showControls = false })

            // Loading is now an OVERLAY above a live interaction layer, never a replacement for it.
            // And it is gated on a COLD open: an episode auto-advance also reloads (clearing
            // hasRenderedFrame), but the viewer is already watching, so taking the screen over is
            // wrong — the bar's inline spinner covers that case.
            if case .failed(let reason) = model.phase {
                ErrorOverlay(reason: reason, canTryAnother: model.canTryAnotherVersion, backdropURL: backdropURL,
                             onRetry: { model.retry() }, onTryAnother: { model.tryAnotherVersion() },
                             onBack: { leave() })
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if model.isColdOpen {
                LoadingOverlay(caption: model.phase == .preparing ? "Preparing…" : "Buffering…",
                               title: model.label, backdropURL: backdropURL)
                    .transition(.opacity)
                    .allowsHitTesting(false)      // the input surface underneath stays live
            }

            // A sync runs for minutes while the film keeps playing, so it reports from up here
            // rather than from inside the sheet that started it. Hidden while the sheet, the
            // browser or the sync pad is up — each of those says it itself.
            if let banner = model.autoSyncBanner, !showSettings, !showSubtitleBrowser, !showManualSync {
                AutoSyncBar(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Same slot as the sync bar and hidden by the same panels, so the two never stack.
            if !showSettings, !showSubtitleBrowser, !showManualSync {
                Color.clear
                    .letterboxdDiaryBar(signal: pushSignal, contentKey: model.contentKey) { state in
                        switch state {
                        case .logged:
                            LetterboxdLoggedBar()
                        case .askingRating(let tmdbID, let current):
                            if ratingEngaged {
                                LetterboxdRatingBar(current: current, focus: $focus) { value in
                                    Task { await answerRating(value, tmdbID: tmdbID) }
                                } onDismiss: {
                                    Task { await dismissRating(tmdbID: tmdbID) }
                                }
                            } else {
                                LetterboxdRatingInvite(current: current)
                            }
                        }
                    }
                    // The confirmation and the invitation are inert; only the stars are pressable —
                    // and they are the ONLY focusable thing this overlay ever mounts.
                    .allowsHitTesting(isRating)
            }

            // Not over a panel: the bar seeds focus to "Play Now" when it appears, which used to
            // pull focus out from under an open Settings or subtitle browser — so the next Select
            // started the next episode. It waits (its countdown held) until the panel closes.
            if model.upNextVisible, !panelOpen, let next = model.nextEpisode {
                // Above the scrub bar when that is up too, never on top of it.
                UpNextBar(model: model, next: next, clearsBar: barSticky)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Last, so it sits above the bar and the Up Next bar — they used to render over the
            // panel.
            if showSettings {
                SettingsPanel(model: model, initialSection: settingsSection,
                              onSearchSubtitles: {
                                  sheetOpenedFrom = nil
                                  showSettings = false
                                  showSubtitleBrowser = true
                              },
                              onSyncToLine: {
                                  sheetOpenedFrom = nil
                                  showSettings = false
                                  model.beginManualSync()
                                  showManualSync = true
                              },
                              // A pick that ends in the film (auto-sync) goes back to the picture,
                              // not to the row.
                              onClose: { sheetOpenedFrom = nil; showSettings = false })
                    .transition(.move(edge: .trailing))
            }

            // Above the panel: the full-screen subtitle browser. Owns its own Menu-to-close.
            if showSubtitleBrowser {
                SubtitleBrowser(model: model, onClose: { showSubtitleBrowser = false })
                    .transition(.opacity)
            }

            // Above the browser: the sync pad. The film keeps playing behind it — that is the
            // whole point, since you are pressing on a line you can hear.
            if showManualSync {
                ManualSyncPanel(model: model,
                                onClose: { showManualSync = false; model.endManualSync() })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            #if DEBUG
            // `-inputHUD`: live readout of what the remote actually delivers. Above everything and
            // non-interactive, so it cannot perturb the very input it is measuring.
            if InputProbe.isEnabled { InputProbeHUD() }
            #endif
        }
        .animation(showSettings ? Theme.Anim.panelOpen : Theme.Anim.panelClose, value: showSettings)
        .animation(showControls ? Theme.Anim.panelOpen : Theme.Anim.panelClose, value: showControls)
        .animation(Theme.Anim.pageFade, value: barShown)
        .animation(Theme.Anim.pageFade, value: showsBigState)
        .animation(Theme.Anim.pageFade, value: showSubtitleBrowser)
        .animation(Theme.Anim.pageFade, value: showManualSync)
        .animation(Theme.Anim.pageFade, value: showEpisodes)
        .animation(Theme.Anim.pageFade, value: model.upNextVisible)
        .animation(Theme.Anim.pageFade, value: model.isColdOpen)
        // The error overlay is gated on `phase`; without animating that value it would pop in
        // rather than fade. Only the ErrorOverlay enters/leaves on a phase change, so this can't
        // animate anything else in the stack.
        .animation(Theme.Anim.pageFade, value: model.phase)
        .animation(Theme.Anim.pageFade, value: model.autoSyncBanner)
        // ONLY for the overlays. While watching, the play/pause press is handled by
        // `PlayerInputSurface` — this modifier depends on SwiftUI's focus system owning the focused
        // view, and the input surface is a focusable UIKit one. Guarding on the same condition
        // means exactly one of the two paths is ever live, so a press can never toggle twice.
        .onPlayPauseCommand { if !inputSurfaceActive { model.togglePlayPause() } }
        .onExitCommand {
            // Menu is the universal "stop what you are doing". A scan first, for the same reason
            // Menu abandons a scrub: whatever is travelling is what the viewer wants stopped, and
            // dismissing the whole player out from under a runaway is not the same thing as
            // stopping it.
            if showManualSync { showManualSync = false; model.endManualSync() }
            else if model.isScanning { model.endScan() }
            else if model.isScrubbing { model.cancelScrub() }  // Menu abandons a scrub
            // The topmost thing first: a panel is drawn over the Up Next bar, so it closes before
            // the bar is dismissed. The other way round, Menu in Settings dismissed Up Next — and
            // with it the auto-advance, so the episode then exited at its end instead.
            else if showSubtitleBrowser { showSubtitleBrowser = false }   // fallback; the browser also self-closes
            // The sheet goes back to the row it was opened from, focus on the same button.
            else if showSettings {
                showSettings = false
                if sheetOpenedFrom != nil { showControls = true }
            }
            else if showControls { showControls = false; sheetOpenedFrom = nil }
            else if showEpisodes { showEpisodes = false }
            else if model.upNextVisible { model.dismissUpNext() }
            // The stars own the remote while they are up, so Menu has to be able to hand it back
            // without also walking out of the film.
            else if isAskingRating,
                    let film = LetterboxdContentKey.tmdbID(fromMovieKey: model.contentKey) {
                Task { await dismissRating(tmdbID: film) }
            }
            else { leave() }
        }
        .onAppear {
            model.start()
            model.revealScrubBar()           // show the bar right away on open (sticky 5s)
        }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }   // so the peek has thumbnails
        }
        // A closing panel hands the remote back to the input surface (which re-enables itself via
        // `isActive`) and re-reveals the bar so there is something on screen to act on.
        .onChange(of: showSettings) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: showControls) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: showEpisodes) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: showSubtitleBrowser) { _, open in if !open { model.revealScrubBar() } }
        .onChange(of: showManualSync) { _, open in if !open { model.revealScrubBar() } }
        // The model ends the session when the file changes under it (an episode swap, a retry):
        // the lines it was syncing belonged to the old subtitle. The panel goes with it — left up,
        // it drew nothing yet still counted as open, holding Up Next and eating the next Menu.
        .onChange(of: model.manualSyncReadout == nil) { _, ended in
            if ended { showManualSync = false }
        }
        // A failed open puts Retry / Back up over everything. Anything focusable left open under
        // it — the row, the sheet, the strip — would still be in the focus engine's reach, behind
        // an overlay that hides it. The subtitle browser and the sync pad go too: they are drawn
        // ABOVE the error overlay, so left up they would cover Retry outright, and the pad's
        // session belongs to a file that no longer plays.
        .onChange(of: hasFailed) { _, failed in
            guard failed else { return }
            showControls = false
            showSettings = false
            sheetOpenedFrom = nil
            showEpisodes = false
            showSubtitleBrowser = false
            if showManualSync { showManualSync = false; model.endManualSync() }
        }
        .onChange(of: model.shouldDismiss) { _, dismissNow in if dismissNow { leave() } }
        // Each prompt starts as an invitation, whatever happened to the last one.
        .onChange(of: isAskingRating) { _, asking in if !asking { ratingEngaged = false } }
        // Up Next does not count down to the next episode underneath an open panel.
        .onChange(of: panelOpen) { _, open in model.upNextHeld = open }
        // The TV button, or the TV going to sleep: pause and keep the place, so the viewer comes
        // back to the frame they left instead of a film that ran on into a suspended app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await model.appDidLeaveForeground() } }
        }
        .onDisappear { Task { await model.teardown() } }
    }

    /// The input surface owns the remote whenever no focusable overlay is up. One source of truth,
    /// because both the surface's own activation and the play/pause routing depend on it.
    ///
    /// The error overlay counts. It puts Retry / Try another / Back on screen as focusable buttons,
    /// and while the surface stayed armed the two competed for focus — and the arrows still drove
    /// skip and hold-to-scan on a player that had already failed.
    ///
    /// The control row counts like the sheet does: it is a row of Buttons, and a focusable sibling
    /// of the surface is exactly what made touch-scrub and arrow clicks mutually exclusive.
    private var inputSurfaceActive: Bool {
        !showSettings && !showControls && !showEpisodes && !model.upNextVisible && !showSubtitleBrowser
            && !showManualSync && !hasFailed && !isRating
    }

    /// Something the viewer opened is up over the picture.
    private var panelOpen: Bool {
        showSettings || showControls || showSubtitleBrowser || showManualSync || showEpisodes
    }

    /// The bar (and with it the top line) is up while the viewer is interacting, mid-buffer, while
    /// a skip badge is counting, or while the row, the sheet or the strip is open.
    ///
    /// Paused keeps it up for as long as the pause lasts. Pausing IS how you arm scrubbing, so the
    /// thing you are about to aim with must be on screen the whole time — not on the 5s reveal
    /// dwell, which timed out mid-scrub and left you dragging a film with no visible playhead. It
    /// comes down by itself when playback resumes.
    ///
    /// While Up Next is up only the STICKY states show it, never the 5s reveal: Up Next lifts
    /// above a bar that is up, and a bar that timed out a few seconds later would drop it ~110pt.
    private var barShown: Bool {
        barSticky || (!model.upNextVisible
                      && (model.scrubBarVisible || model.isBuffering || model.skipFeedback != nil))
    }

    /// The states that hold the bar up until the viewer changes them — not on a timer.
    private var barSticky: Bool {
        model.phase == .paused || model.isScrubbing || showEpisodes || showControls || showSettings
    }

    /// The top line follows the bar, except over the screens that cover the picture.
    private var topBarShown: Bool {
        barShown && !hasFailed && !model.isColdOpen && !showSubtitleBrowser && !showManualSync
    }

    private var showsBigState: Bool {
        model.phase == .paused && !model.isScrubbing && !model.isColdOpen && !panelOpen
    }

    /// The control row's buttons. Episodes only for a show whose season list has loaded — the
    /// button would otherwise open nothing.
    private var controls: [PlayerControl] {
        let base: [PlayerControl] = [.subtitles, .audio, .speed]
        return model.isEpisode && !model.seasonEpisodes.isEmpty ? base + [.episodes] : base
    }

    /// A control-row button was pressed: the sheet at that section, or the episode strip.
    private func choose(_ control: PlayerControl) {
        showControls = false
        if let section = control.section {
            settingsSection = section
            sheetOpenedFrom = control
            showSettings = true
        } else {
            sheetOpenedFrom = nil
            showEpisodes = true
            Task { await model.loadSeasonEpisodes() }
        }
    }

    /// The stars are up and own the remote — only once the viewer has pressed Up to answer.
    ///
    /// The prompt arrives while the film is still playing (its credits, or five minutes from the
    /// end when nothing says where the film ends), and it used to mount the stars at once with focus
    /// seeded on the first one. The viewer's next Select — meant to pause — filed 1/10 to Letterboxd,
    /// and the arrows moved between stars instead of skipping. Until Up, the prompt is an invitation
    /// and the remote keeps doing what it was doing.
    private var isRating: Bool { isAskingRating && ratingEngaged }

    /// True while a diary entry for THIS film is held waiting on a rating.
    ///
    /// Load-bearing twice over: it is what puts the stars in reach of the remote, and what keeps
    /// `PlayerInputSurface` from competing with them for it. A focusable sibling at rest is what
    /// made touch-scrub and directional clicks mutually exclusive in the first place, so the stars
    /// may only ever exist while this is true.
    private var isAskingRating: Bool {
        guard let prompt = pushSignal?.ratingPrompt,
              let film = LetterboxdContentKey.tmdbID(fromMovieKey: model.contentKey)
        else { return false }
        return prompt.tmdbID == film
    }

    private func answerRating(_ value: Int?, tmdbID: Int) async {
        await filmRating?.rate(value, contentKey: model.contentKey, tmdbID: tmdbID)
        model.revealScrubBar()
    }

    private func dismissRating(tmdbID: Int) async {
        await filmRating?.dismiss(tmdbID: tmdbID)
        model.revealScrubBar()
    }

    /// Leave the player: silence it at once (see `PlayerModel.beginClosing`), then dismiss. The
    /// teardown itself still runs from `.onDisappear`.
    private func leave() {
        model.beginClosing()
        dismiss()
    }

    private var hasFailed: Bool {
        if case .failed = model.phase { return true } else { return false }
    }

    /// Down from the stage: collapse the episode strip if it's open, else open the control row.
    private func openControlsOrCloseStrip() {
        if showEpisodes { showEpisodes = false }
        else { sheetOpenedFrom = nil; showControls = true }
    }

    /// Up from the stage: lift the episode strip on a show, otherwise just wake the bar.
    ///
    /// This is what the resting peek has always advertised — a "⌃ Episodes" hint under the scrub
    /// bar — but nothing was wired to it: `onEpisodes` was passed to `PlayerBottomBar` and never
    /// called from there, and `openSettingsOrEpisodes` only ever CLOSES the strip. So `showEpisodes`
    /// could never become true and the whole in-player episode picker was unreachable.
    private func openEpisodesOrRevealBar() {
        // A pending Letterboxd prompt claims Up: it is the deliberate step into rating.
        if isAskingRating, !ratingEngaged { ratingEngaged = true; return }
        guard model.isEpisode, !model.seasonEpisodes.isEmpty, !showEpisodes else {
            model.revealScrubBar()
            return
        }
        showEpisodes = true
        Task { await model.loadSeasonEpisodes() }
    }
}

/// The bottom-anchored player cluster: the scrub bar on TOP; beneath it the ⌄ hint, the control
/// row or the episode strip. Because they're stacked in one bottom-pinned column, the bar
/// automatically rides up as the row or the strip opens — it can never overlap them or float to
/// the middle of the screen.
private struct PlayerBottomBar: View {
    @Bindable var model: PlayerModel
    let barShown: Bool
    @Binding var showEpisodes: Bool
    let showControls: Bool
    let showSettings: Bool
    /// The ⌄ under the bar — not while Up Next holds the remote.
    let showsHint: Bool
    let controls: [PlayerControl]
    let controlsFocus: PlayerControl?
    let onChoose: (PlayerControl) -> Void
    let onCloseControls: () -> Void

    private var hasEpisodes: Bool { model.isEpisode && !model.seasonEpisodes.isEmpty }

    /// "⌃ Episodes" above the bar, on a show. Out of the way of whatever rides the knob — the
    /// skip badge, the scrub time — which shares that band.
    private var showsEpisodePeek: Bool {
        hasEpisodes && barShown && !showEpisodes && !showControls && !model.upNextVisible
            && model.skipFeedback == nil && !model.isScrubbing
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if barShown {
                // The remaining time sits under the side sheet's edge while it is up.
                ScrubBar(model: model, buffering: model.isBuffering, showsRemaining: !showSettings)
                    .overlay(alignment: .topTrailing) {
                        EpisodePeek()
                            .offset(y: -44)
                            .opacity(showsEpisodePeek ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if showControls {
                PlayerControlRow(controls: controls, onChoose: onChoose, onClose: onCloseControls,
                                 initialFocus: controlsFocus)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showSettings {
                // The row's room, held while the sheet it opened is up: the bar stays exactly where
                // it was with the row, instead of dropping as the sheet slides in and climbing back
                // when Menu returns to the row.
                Color.clear
                    .frame(height: PlayerControlRow.height)
                    .allowsHitTesting(false)
            } else if hasEpisodes && showEpisodes {
                EpisodeStripExpanded(model: model, onPlay: { showEpisodes = false },
                                     onClose: { showEpisodes = false })
                    .transition(.opacity)
            } else if barShown {
                // Down opens the control row. Faded, not removed, under Up Next, so the bar keeps its
                // place.
                Image(systemName: "chevron.down")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .opacity(showsHint ? 1 : 0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // Lines the bar's left edge up with the top line's title and the control row.
        .padding(.horizontal, PlayerLayout.sideInset)
        // A soft bottom scrim so the bar, the row and the episode stills stay readable over bright
        // scenes.
        .background(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.4), location: 0.5),
                                   .init(color: .black.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: showEpisodes ? 480 : 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(barShown ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(Theme.Anim.pageFade, value: barShown)
        .animation(Theme.Anim.pageFade, value: showEpisodes)
        .animation(Theme.Anim.focus, value: showsEpisodePeek)
    }
}

/// Resting hint above the bar on a show: Up lifts the season's episodes.
private struct EpisodePeek: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.up")
                .font(.system(size: 20, weight: .semibold))
            Text("Episodes").font(.seret(22, .semibold))
        }
        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.75))
        .fixedSize()
    }
}

/// Open state: the season's episodes as focusable still cards. Selecting a downloaded one switches
/// playback in place; not-downloaded ones are dimmed + a ⬇︎ glyph. Seeds focus to the current one.
private struct EpisodeStripExpanded: View {
    @Bindable var model: PlayerModel
    let onPlay: () -> Void
    /// Down from the cards — the strip opened with Up.
    var onClose: () -> Void = {}
    @FocusState private var focused: String?

    private static let closeTarget = "close-strip"

    private var currentID: String? {
        model.currentEpisode.map { "\($0.season)x\($0.number)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // Eager, not lazy: a season is a few dozen cards at most, and the playing
                    // episode's card has to EXIST for focus to land on it. Lazily, a card past the
                    // first screenful was not built yet when the strip opened, the focus write was
                    // dropped, and on a long season focus landed on an early episode instead.
                    HStack(spacing: 22) {
                        ForEach(model.seasonEpisodes) { ep in
                            Button { if let owned = ep.owned { model.play(owned); onPlay() } } label: { card(ep) }
                                .buttonStyle(FocusCardStyle(cornerRadius: 10))
                                .disabled(!ep.isPlayable)
                                .id(ep.id)
                                .focused($focused, equals: ep.id)
                        }
                    }
                    .padding(.vertical, 10)            // just enough room for the focus lift
                }
                // Snug to the cards (stills only now, no name labels) so the strip sits TIGHT under the
                // scrub bar — a horizontal ScrollView is greedy vertically and would otherwise fill it.
                .frame(height: 140)
                .defaultFocus($focused, currentID)
                .onAppear {
                    guard let id = currentID else { return }
                    proxy.scrollTo(id, anchor: .center)
                    focused = id
                }
            }
            // The only way to hear DOWN from a card: a thin focus target under the row. The cards
            // cannot take `.onMoveCommand` — on a focusable row it swallows the arrows and traps
            // focus — and with the input surface off while the strip is up, nothing else listens.
            Color.clear
                .frame(maxWidth: .infinity).frame(height: 2)
                .focusable()
                .focused($focused, equals: Self.closeTarget)
        }
        .onChange(of: focused) { _, new in if new == Self.closeTarget { onClose() } }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ ep: PlayerModel.PlayerEpisode) -> some View {
        let isCurrent = ep.season == model.currentEpisode?.season && ep.number == model.currentEpisode?.number
        return VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: TMDBClient.imageURL(path: ep.stillPath, size: "w300"),
                        contentMode: .fill) { _ in Rectangle().fill(Theme.Palette.glassFaint) }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(ep.number)")
                        .font(.seret(.caption1, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.Palette.badgeBacking, in: Capsule())
                        .padding(6)
                }
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.Palette.strokeStrong, lineWidth: 4)
                    } else if !ep.isPlayable {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.artDim)
                            .overlay {
                                Image(systemName: "arrow.down.circle").font(.title2)
                                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
                            }
                    }
                }
        }
        .opacity(ep.isPlayable ? 1 : 0.7)
    }
}
