import DebridUI
import SwiftUI

extension FocusedValues {
    /// The focused window's shell, so menu commands act on the window in front.
    @Entry var shellModel: ShellModel?
    /// The player in front, so the Playback menu drives it. Nil when nothing is playing.
    @Entry var playerCommands: PlayerCommands?
}

/// What the Playback menu can do to the player in front — the same intents its keys map to.
struct PlayerCommands {
    let isEpisode: Bool
    let hasNextEpisode: Bool
    let perform: (PlayerKeyCommand) -> Void
}

/// Menu-bar commands: File (Add by Magnet), View (sidebar), Go, Library and Playback.
struct SeretCommands: Commands {
    let session: AppSession
    @FocusedValue(\.shellModel) private var shell
    @FocusedValue(\.playerCommands) private var player

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add by Magnet\u{2026}") { shell?.requestMagnet() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(shell?.titleOnTop == nil || shell?.playback != nil)
        }
        CommandGroup(before: .sidebar) {
            Button(shell?.isSidebarCollapsed == true ? "Expand Sidebar" : "Collapse Sidebar") {
                withAnimation(Theme.Motion.standard) { shell?.toggleSidebar() }
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .disabled(shell == nil)
            Divider()
        }
        CommandMenu("Go") {
            ForEach(SidebarSection.allCases) { section in
                Button(section.title) { shell?.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(section.shortcutDigit)")), modifiers: .command)
                    .disabled(shell == nil)
            }
            Divider()
            Button("Search") { shell?.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(shell == nil || shell?.playback != nil)
            Divider()
            Button("Back") { shell?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(shell?.canGoBack != true || shell?.playback != nil)
            Button("Forward") { shell?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(shell?.canGoForward != true || shell?.playback != nil)
        }
        // Playback mirrors the player's keys (spec §7.3). The bare keys (Space, ←, S…) are shown in
        // the titles, not set as key equivalents: a bare-key menu shortcut would swallow that key
        // in every text field in the app.
        CommandMenu("Playback") {
            Group {
            Button("Play / Pause   Space") { player?.perform(.playPause) }
            Button("Back 10 Seconds   ←") { player?.perform(.skip(-10)) }
            Button("Forward 10 Seconds   →") { player?.perform(.skip(10)) }
            Divider()
            Button("Volume Up   ↑") { player?.perform(.volume(10)) }
            Button("Volume Down   ↓") { player?.perform(.volume(-10)) }
            Button("Mute   M") { player?.perform(.mute) }
            Divider()
            Button("Slower   [") { player?.perform(.speed(-1)) }
            Button("Faster   ]") { player?.perform(.speed(1)) }
            Divider()
            Button("Audio & Subtitles…   S") { player?.perform(.toggleTracks) }
            Button("Subtitle Earlier   ⌥←") { player?.perform(.subtitleDelay(-0.5)) }
            Button("Subtitle Later   ⌥→") { player?.perform(.subtitleDelay(0.5)) }
            Divider()
            Button("Episodes   E") { player?.perform(.toggleEpisodes) }
                .disabled(player?.isEpisode != true)
            Button("Next Episode   N") { player?.perform(.nextEpisode) }
                .disabled(player?.hasNextEpisode != true)
            Divider()
            Button("Toggle Full Screen   F") { player?.perform(.toggleFullScreen) }
            Button("Close Player   Esc") { player?.perform(.escape) }
            }
            .disabled(player == nil)
        }
        CommandMenu("Library") {
            Button("Refresh") { session.libraryStore?.reload() }
                .keyboardShortcut("r")
                .disabled(session.libraryStore == nil)
        }
    }
}
