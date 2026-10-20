import SwiftUI

/// A rail's heading, as the mockups draw it: bold title-case white, with an optional quiet
/// "See All" on the right.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.Typo.railTitle())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.md)
            if let action {
                Button("See All", action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }
}
