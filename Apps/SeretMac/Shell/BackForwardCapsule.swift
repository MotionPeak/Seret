import SwiftUI

/// The Mac's own back/forward control (⌘[ / ⌘]). `NavigationStack` can only pop, and the app's
/// own system toolbar back button is hidden (`SectionStack`), so this is the only way back or
/// forward — absent entirely when neither direction is possible.
struct BackForwardCapsule: View {
    @Bindable var model: ShellModel
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        if model.canGoBack || model.canGoForward {
            HStack(spacing: 2) {
                chevron("chevron.left", enabled: model.canGoBack, help: "Back (⌘[)") { model.goBack() }
                chevron("chevron.right", enabled: model.canGoForward, help: "Forward (⌘])") { model.goForward() }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: Capsule())
            .padding(.leading, pageLeadingInset)
            .padding(.top, 14)
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Palette.textPrimary)
        .opacity(enabled ? 0.35 : 0.15)
        .disabled(!enabled)
        .help(help)
    }
}
