import AppKit
import DebridUI
import SwiftUI

/// The player, in the window: black background, the real video surface, loading/buffering/failure
/// overlays, and the keyboard map. Full screen and the HUD proper (scrubber, transport, volume,
/// tracks panel) arrive in Task 7 — this is the engine lifecycle + keys + display-awake slice.
struct PlayerScreen<Surface: View>: View {
    let model: PlayerModel
    let onClose: () -> Void
    @ViewBuilder let surface: () -> Surface

    @State private var windowRef = WindowRef()
    @State private var sleepGuard = DisplaySleepGuard()
    @State private var muteMemory = MuteMemory()
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black
            surface()
            PlayerStateOverlays(model: model, onClose: onClose)
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
        .onAppear {
            model.start()
            isFocused = true
        }
        .onChange(of: model.shouldDismiss) { _, done in
            if done { onClose() }
        }
        .onChange(of: model.phase, initial: true) { _, phase in
            sleepGuard.update(isPlaying: phase == .playing)
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
            switch PlayerEscape.next(panelOpen: false, isFullScreen: windowRef.isFullScreen) {
            case .closePanel:
                break   // no panel until Task 7
            case .exitFullScreen:
                windowRef.window?.toggleFullScreen(nil)
            case .closePlayer:
                onClose()
            }
        }
        // Re-assert focus after every command: a click on the picture or (Task 7) a panel closing
        // can steal it, and arrows must keep reaching this view, never the VLC NSView underneath.
        isFocused = true
    }
}
