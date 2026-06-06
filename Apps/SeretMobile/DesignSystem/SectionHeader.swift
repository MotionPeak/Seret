import SwiftUI

/// Uppercase gold section label with optional trailing action.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title.uppercased()).font(Theme.Typo.label())
                .tracking(1.5).foregroundStyle(Theme.Palette.gold)
            Spacer()
            if let action {
                Button("See all", action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }
}
