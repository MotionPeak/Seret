import SwiftUI

/// A pill button style for in-content selectors (segment / filter rows). Explicitly controls BOTH
/// fill and text by focus + selection, so it never renders white-on-white the way a
/// default/bordered tvOS button does:
///   focused             → white pill, dark text
///   selected (no focus) → glass pill, white text
///   otherwise           → white 8% pill, secondary text
///
/// Usage: `Button(title) { … }.buttonStyle(SeretPillStyle(selected: isSelected))`
struct SeretPillStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, selected: selected)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused: Bool
        var body: some View {
            configuration.label
                .font(.seretHeadline)
                .foregroundStyle(textColor)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? Theme.Anim.buttonFocusScale : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(Theme.Anim.focus, value: focused)
        }
        private var textColor: Color {
            if focused { return Theme.Palette.onFocus }
            return selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
        }
        private var fill: Color {
            if focused { return Theme.Palette.focus }
            return selected ? Theme.Palette.glass : Color.white.opacity(0.08)
        }
    }
}
