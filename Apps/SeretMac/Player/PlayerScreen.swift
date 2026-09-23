import AppKit
import DebridUI
import SwiftUI

/// The player, in the window: black background, the real video surface, loading/buffering/failure
/// overlays, the windowed HUD (top bar, transport panel, tracks panel, Up Next), and the keyboard
/// map. Full screen toggles the real window; the HUD is sized in points and never scales with it.
struct PlayerScreen<Surface: View>: View {
    let model: PlayerModel
    let onClose: () -> Void
    @ViewBuilder let surface: () -> Surface

    @State private var windowRef = WindowRef()
    @State private var sleepGuard = DisplaySleepGuard()
    @State private var muteMemory = MuteMemory()
    @State private var hud: HUDVisibility
    @State private var tracksPanelOpen: Bool
    @FocusState private var isFocused: Bool

    /// `hud` is injectable so the harness can pin auto-hide off (`HUDVisibility(delay: nil)`), and
    /// `tracksPanelOpen` so it can start the Audio & Subtitles panel already open — the real app
    /// always takes the defaults (a real-delay `HUDVisibility`, the panel closed).
    init(model: PlayerModel, onClose: @escaping () -> Void, hud: HUDVisibility = HUDVisibility(),
        tracksPanelOpen: Bool = false, @ViewBuilder surface: @escaping () -> Surface) {
        self.model = model
        self.onClose = onClose
        self.surface = surface
        _hud = State(wrappedValue: hud)
        _tracksPanelOpen = State(wrappedValue: tracksPanelOpen)
    }

    var body: some View {
        ZStack {
            Color.black
            surface()
            tapLayer
            PlayerStateOverlays(model: model, onClose: onClose)
            PlayerHUD(model: model, hud: hud, windowRef: windowRef, tracksPanelOpen: $tracksPanelOpen,
                     onClose: onClose,
                     onToggleFullScreen: { perform(.toggleFullScreen) },
                     onToggleMute: { perform(.mute) })
        }
        .ignoresSafeArea()
        .background(WindowReader(ref: windowRef))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in
            // `.down` only: key-repeat must never machine-gun skips.
            guard let command = PlayerKeyCommand(key: press.key, characters: press.characters,
                                                 modifiers: press.modifiers) else { return .ignored }
            perform(command)
            return .handled
        }
        .onContinuousHover { phase in
            if case .active = phase { hud.poke() }
        }
        .onChange(of: hud.isVisible) { _, visible in
            guard model.phase == .playing else { return }
            if visible {
                windowRef.restoreChrome()
            } else {
                NSCursor.setHiddenUntilMouseMoves(true)
                windowRef.setTrafficLightsHidden(true)
            }
        }
        .onChange(of: tracksPanelOpen) { _, open in
            hud.panelOpen = open
            if !open { isFocused = true }   // a panel closing must hand the keyboard back
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
            Task { await model.teardown() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard (note.object as? NSWindow) === windowRef.window else { return }
            windowRef.setFullScreen(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard (note.object as? NSWindow) === windowRef.window else { return }
            windowRef.setFullScreen(false)
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
        case .escape:
            switch PlayerEscape.next(panelOpen: tracksPanelOpen, isFullScreen: windowRef.isFullScreen) {
            case .closePanel:
                tracksPanelOpen = false
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
