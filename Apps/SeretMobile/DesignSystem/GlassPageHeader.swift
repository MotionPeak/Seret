import SwiftUI

/// A root page's own top bar, as the mockups draw it: a big title on the left and glass circle
/// buttons on the right, floating over the page with the content scrolling underneath.
///
/// Mounted with `.glassPageHeader(…)`, which also hides the system navigation bar on that page
/// only — a page pushed on top keeps its normal bar and back button.
struct GlassPageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            Text(title)
                .font(Theme.Typo.pageTitle())
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Legible over bright art without a visible box behind it.
                .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.md)
            GlassGroup(spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.md) { trailing }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.md)
        .background(alignment: .top) {
            // A soft shade, not a bar: enough that the title reads over scrolled posters, faded
            // out so the art still shows through as it does in the mockups.
            LinearGradient(colors: [Theme.Palette.shadeInk.opacity(0.72), Theme.Palette.shadeInk.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Puts a `GlassPageHeader` on top of this page and hides the system navigation bar for it.
    func glassPageHeader<Trailing: View>(_ title: String,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        let header = GlassPageHeader(title: title, trailing: trailing)
        return self
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
    }
}
