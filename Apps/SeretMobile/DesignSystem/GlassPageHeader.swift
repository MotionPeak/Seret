import SwiftUI

/// A root page's own top bar, as the mockups draw it: a big title on the left and glass circle
/// buttons on the right, floating over the page with the content scrolling underneath.
///
/// Mounted with `.glassPageHeader(…)`, which also hides the system navigation bar on that page
/// only — a page pushed on top keeps its normal bar and back button.
struct GlassPageHeader<Trailing: View>: View {
    let title: String
    /// How firm the shade behind the bar is, 0…1. Home keeps it faint while its hero art is under
    /// the bar and firms it up once the art has scrolled away.
    var shade: Double = 1
    @ViewBuilder var trailing: Trailing
    @Environment(\.horizontalSizeClass) private var hSize

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
            // The container's merge distance sits BELOW the visual gap, so iOS 26 keeps the circles
            // apart at rest and only blends them when they genuinely touch.
            GlassGroup(spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.md) { trailing }
            }
        }
        // On the rails' own leading line, so the page title and the rail titles align.
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.md)
        .background(alignment: .top) {
            // A soft shade, not a bar: enough that the title reads over scrolled posters, faded
            // out so the art still shows through as it does in the mockups.
            // Runs a little past the bar, so a rail title sliding under "Movies" is already faint
            // by the time it meets it.
            LinearGradient(stops: [.init(color: Theme.Palette.shadeInk.opacity(0.9 * shade), location: 0),
                                   .init(color: Theme.Palette.shadeInk.opacity(0.75 * shade), location: 0.55),
                                   .init(color: Theme.Palette.shadeInk.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -28)
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
