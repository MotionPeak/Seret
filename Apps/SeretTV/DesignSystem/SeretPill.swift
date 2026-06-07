import SwiftUI

/// A Gold Glass pill button style for in-content selectors (segment / filter rows). Explicitly
/// controls BOTH fill and text by focus + selection, so it never renders white-on-white the way
/// a default/bordered tvOS button does:
///   focused           → solid gold pill, black text
///   selected (no focus)→ faint gold pill, gold text
///   otherwise          → faint white pill, secondary text
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
                .font(.headline)
                .foregroundStyle(textColor)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? 1.06 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        private var textColor: Color {
            if focused { return .black }
            return selected ? Theme.Palette.gold : Theme.Palette.textSecondary
        }
        private var fill: AnyShapeStyle {
            if focused { return AnyShapeStyle(Theme.Palette.goldGradient) }
            if selected { return AnyShapeStyle(Theme.Palette.gold.opacity(0.18)) }
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
    }
}
