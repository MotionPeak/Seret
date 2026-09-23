import AppKit
import DebridUI
import SwiftUI

/// The player, in the window: black background, the real video surface, loading/buffering/failure
/// overlays, the windowed HUD (top bar, transport panel, tracks panel, Up Next), and the keyboard
/// map. Full screen toggles the real window; the HUD is sized in points and never scales with it.
struct PlayerScreen<Surface: View>: View {
    let model: PlayerModel
    let onClose: () -> Void
    /// Runs after `teardown()` returns — the engine is stopped and the final position written.
    let onTornDown: () -> Void
    /// Passed in rather than read from the environment (a non-optional Observable read traps when
    /// the object doesn't cross a presentation boundary); nil in previews.
    let pushSignal: LetterboxdPushSignal?
    let filmRating: FinishedFilmRating?
    @ViewBuilder let surface: () -> Surface

    @State private var windowRef: WindowRef
    @State private var sleepGuard = DisplaySleepGuard()
    @State private var muteMemory = MuteMemory()
    @State private var hud: HUDVisibility
    @State private var tracksPanelOpen: Bool
    @State private var panelMode: TracksPanelMode = .tracks
    @State private var episodesOpen = false
    /// The film the credits rating bar is asking about, while it is up — what 1…0 rate.
    @State private var ratingTarget: RatingTarget?
    @FocusState private var isFocused: Bool

    private struct RatingTarget: Equatable { let tmdbID: Int; let current: Int? }

    /// `hud` is injectable so the harness can pin auto-hide off (`HUDVisibility(delay: nil)`),
    /// `tracksPanelOpen` so it can start the Audio & Subtitles panel already open, and `windowRef` so
    /// it can force the full-screen HUD style without a real `NSWindow` full-screen transition — the
    /// real app always takes the defaults (a real-delay `HUDVisibility`, the panel closed, windowed).
    init(model: PlayerModel, onClose: @escaping () -> Void, onTornDown: @escaping () -> Void = {},
        pushSignal: LetterboxdPushSignal? = nil, filmRating: FinishedFilmRating? = nil,
        hud: HUDVisibility = HUDVisibility(),
        tracksPanelOpen: Bool = false, windowRef: WindowRef = WindowRef(),
        @ViewBuilder surface: @escaping () -> Surface) {
        self.model = model
        self.onClose = onClose
        self.onTornDown = onTornDown
        self.pushSignal = pushSignal
        self.filmRating = filmRating
        self.surface = surface
        _hud = State(wrappedValue: hud)
        _tracksPanelOpen = State(wrappedValue: tracksPanelOpen)
        _windowRef = State(wrappedValue: windowRef)
    }

    var body: some View {
        ZStack {
            // The surface is an OVERLAY of the black layer, never a ZStack sibling: an overlay is
            // offered exactly the window's size and cannot grow its parent. As a sibling, anything
            // wider than the window (an aspect-filled frame, an NSView reporting its video size)
            // widened the whole ZStack past the window edges, pushing the top bar under the traffic
            // lights and the tracks panel's trailing column off screen.
            Color.black
                .overlay { surface() }
                .clipped()
            tapLayer
            PlayerStateOverlays(model: model, onClose: onClose)
            PlayerHUD(model: model, hud: hud, windowRef: windowRef, tracksPanelOpen: $tracksPanelOpen,
                     panelMode: $panelMode, episodesOpen: $episodesOpen,
                     onClose: onClose,
                     onToggleFullScreen: { perform(.toggleFullScreen) },
                     onToggleMute: { perform(.mute) })
        }
        .overlay(alignment: .top) { banners }
        .focusedSceneValue(\.playerCommands,
                           PlayerCommands(isEpisode: model.isEpisode, hasNextEpisode: model.hasNextEpisode,
                                          perform: { perform($0) }))
        .ignoresSafeArea()
        .background(WindowReader(ref: windowRef))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: [.down, .repeat, .up]) { press in
            handleKey(press)
        }
        .onContinuousHover { phase in
            if case .active = phase { hud.poke() }
        }
        .onChange(of: hud.isVisible) { _, visible in
            // Showing is unconditional: pausing is itself what re-shows the HUD, and by then the
            // phase is no longer `.playing` — guarding both branches left the window buttons
            // invisible for the whole pause.
            if visible {
                windowRef.restoreChrome()
            } else if model.phase == .playing {
                NSCursor.setHiddenUntilMouseMoves(true)
                windowRef.setTrafficLightsHidden(true)
            }
        }
        .onChange(of: tracksPanelOpen) { _, open in
            hud.panelOpen = open || episodesOpen
            if !open {
                if panelMode == .sync { model.endManualSync() }
                panelMode = .tracks
                isFocused = true   // a panel closing must hand the keyboard back
            }
        }
        .onChange(of: episodesOpen) { _, open in
            hud.panelOpen = open || tracksPanelOpen
            if !open { isFocused = true }
        }
        .task(id: model.currentEpisode?.season) {
            if model.isEpisode { await model.loadSeasonEpisodes() }
        }
        .onAppear {
            model.start()
            isFocused = true
        }
        .onChange(of: model.shouldDismiss) { _, done in
            if done { onClose() }
        }
        .onChange(of: model.phase, initial: true) { _, phase in
            sleepGuard.update(isPlaying: phase == .playing)
            hud.isPlaying = phase == .playing
        }
        .onDisappear {
            sleepGuard.release()
            windowRef.restoreChrome()
            // Keeps the model (and so the engine) alive until it has actually stopped.
            Task {
                await model.teardown()
                onTornDown()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard (note.object as? NSWindow) === windowRef.window else { return }
            windowRef.setFullScreen(true)
            hud.isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard (note.object as? NSWindow) === windowRef.window else { return }
            windowRef.setFullScreen(false)
            hud.isFullScreen = false
        }
    }

    /// A clear full-area layer under the HUD: double-click toggles full screen, a single click
    /// toggles play/pause (SwiftUI delays the single click until the double-click window passes —
    /// the same behaviour QuickTime has).
    private var tapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { perform(.toggleFullScreen) }
            .onTapGesture {
                model.togglePlayPause()
                hud.poke()
                isFocused = true
            }
    }

    // MARK: - Banners (top centre, below the top bar while the HUD is up)

    private var banners: some View {
        VStack(spacing: 8) {
            if let banner = model.autoSyncBanner {
                AutoSyncBar(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Color.clear.frame(height: 0)
                .letterboxdDiaryBar(signal: pushSignal, contentKey: model.contentKey) { state in
                    switch state {
                    case .logged:
                        LetterboxdLoggedBar()
                    case .askingRating(let tmdbID, let current):
                        LetterboxdRatingBar(current: current) { value in
                            Task { await filmRating?.rate(value, contentKey: model.contentKey, tmdbID: tmdbID) }
                        } onDismiss: {
                            Task { await filmRating?.dismiss(tmdbID: tmdbID) }
                        }
                        .onAppear { ratingTarget = RatingTarget(tmdbID: tmdbID, current: current) }
                        .onChange(of: current) { _, now in ratingTarget = RatingTarget(tmdbID: tmdbID, current: now) }
                        .onDisappear { ratingTarget = nil }
                    }
                }
        }
        .padding(.top, hud.isVisible ? (windowRef.isFullScreen ? 64 : 84) : 18)
        .animation(Theme.Motion.fade, value: model.autoSyncBanner)
        .animation(Theme.Motion.fade, value: hud.isVisible)
    }

    // MARK: - Keys

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // A "Sync to a line" session owns ↑↓←→ Return Esc while it is open.
        if model.manualSyncReadout != nil, tracksPanelOpen, panelMode == .sync {
            guard press.phase != .up, let key = ManualSyncKey(key: press.key, modifiers: press.modifiers)
            else { return .ignored }
            switch key {
            case .moveLine(let delta): model.moveSyncLine(by: delta)
            case .mark: if press.phase == .down { model.markSyncMoment() }
            case .nudge(let delta): model.nudgeSyncOffset(by: delta)
            case .done:
                model.endManualSync()
                panelMode = .tracks
            }
            return .handled
        }

        // Hold ←/→ to scan: the first auto-repeat starts it, key-up ends it. A plain press skips on
        // `.down` as before; key-repeat never machine-guns skips.
        let isPlainArrow = press.modifiers.isDisjoint(with: [.command, .control, .option])
            && (press.key == .leftArrow || press.key == .rightArrow)
        if isPlainArrow {
            switch press.phase {
            case .repeat:
                if !model.isScanning { model.beginScan(direction: press.key == .leftArrow ? -1 : 1) }
                hud.poke()
                return .handled
            case .up:
                if model.isScanning { model.endScan() }
                return .handled
            default:
                break
            }
        }
        guard press.phase == .down,
              let command = PlayerKeyCommand(key: press.key, characters: press.characters,
                                             modifiers: press.modifiers) else { return .ignored }
        if case .rate = command, ratingTarget == nil { return .ignored }
        perform(command)
        return .handled
    }

    private func perform(_ command: PlayerKeyCommand) {
        switch command {
        case .playPause:
            model.togglePlayPause()
        case .skip(let delta):
            model.skip(delta)
        case .volume(let delta):
            muteMemory.unmuteForVolumeChange()
            model.setVolume(model.volumePercent + delta)
        case .mute:
            model.setVolume(muteMemory.toggle(current: model.volumePercent))
        case .toggleFullScreen:
            windowRef.window?.toggleFullScreen(nil)
        case .subtitleDelay(let delta):
            model.adjustSubtitleDelay(by: delta)
        case .toggleTracks:
            tracksPanelOpen.toggle()
        case .toggleEpisodes:
            if model.isEpisode { episodesOpen.toggle() }
        case .nextEpisode:
            if model.hasNextEpisode { model.playNext() }
        case .speed(let direction):
            model.setPlaybackSpeed(PlaybackSpeeds.step(from: model.playbackSpeed, direction: direction))
        case .rate(let value):
            if let target = ratingTarget {
                Task {
                    await filmRating?.rate(target.current == value ? nil : value,
                                           contentKey: model.contentKey, tmdbID: target.tmdbID)
                }
            }
        case .escape:
            switch PlayerEscape.next(syncActive: model.manualSyncReadout != nil && panelMode == .sync,
                                     panelOpen: tracksPanelOpen || episodesOpen,
                                     isFullScreen: windowRef.isFullScreen) {
            case .endSync:
                model.endManualSync()
                panelMode = .tracks
            case .closePanel:
                if episodesOpen { episodesOpen = false } else { tracksPanelOpen = false }
            case .exitFullScreen:
                windowRef.window?.toggleFullScreen(nil)
            case .closePlayer:
                onClose()
            }
        }
        hud.poke()
        // Re-assert focus after every command: a click on the picture or a panel closing can steal
        // it, and arrows must keep reaching this view, never the VLC NSView underneath.
        isFocused = true
    }
}
