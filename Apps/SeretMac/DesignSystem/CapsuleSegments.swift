import SwiftUI

/// Mockup 3's `.seg` control: a white-6% capsule track with a hairline, its options 13 pt semibold
/// `textSecondary`, and the selected one lifted onto a white-14% fill in `textPrimary` — the fill
/// sliding between options with `matchedGeometryEffect`. Reduce Motion drops the slide (a cut,
/// not a cross-fade — the fill still moves, just without animation).
struct CapsuleSegments<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let selection: Option
    let onSelect: (Option) -> Void

    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "seret.segment.selection", in: space)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: selection)
    }
}
