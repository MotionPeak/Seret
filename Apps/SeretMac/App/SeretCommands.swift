import DebridUI
import SwiftUI

extension FocusedValues {
    /// The focused window's shell, so menu commands act on the window in front.
    @Entry var shellModel: ShellModel?
}

/// Menu-bar commands. Later phases add File and Playback.
struct SeretCommands: Commands {
    let session: AppSession
    @FocusedValue(\.shellModel) private var shell

    var body: some Commands {
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
            Button("Back") { shell?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(shell?.canGoBack != true || shell?.playback != nil)
            Button("Forward") { shell?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(shell?.canGoForward != true || shell?.playback != nil)
        }
        CommandMenu("Library") {
            Button("Refresh") { session.libraryStore?.reload() }
                .keyboardShortcut("r")
                .disabled(session.libraryStore == nil)
        }
    }
}
