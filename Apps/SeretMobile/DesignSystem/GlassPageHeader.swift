import SwiftUI

/// A root page's own top bar, as the mockups draw it: a big title on the left and glass circle
/// buttons on the right, floating over the page with the content scrolling underneath.
///
/// Mounted with `.glassPageHeader(…)`, which also hides the system navigation bar on that page
/// only — a page pushed on top keeps its normal bar and back button.
struct GlassPageHeader<Trailing: View>: View {
    let title: String
    /// A quiet line under the title (the Watchlist's "256 films").
    var subtitle: String? = nil
    /// How firm the shade behind the bar is, 0…1. Home keeps it faint while its hero art is under
    /// the bar and firms it up once the art has scrolled away.
    var shade: Double = 1
    @ViewBuilder var trailing: Trailing
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Typo.pageTitle())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            // Legible over bright art without a visible box behind it.
            .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
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
            // Legibility for the title and circles over whatever scrolls beneath: held firm to the
            // bar's bottom edge, then faded out just below it (`TopBarShade`). iOS 18 has no blur
            // behind a custom bar, so a gradient that faded from the very top let rail titles
            // run straight through "Movies" and the status-bar clock.
            TopBarShade(opacity: shade).ignoresSafeArea(edges: .top)
        }
    }
}

extension View {
    /// Puts a `GlassPageHeader` on top of this page and hides the system navigation bar for it.
    func glassPageHeader<Trailing: View>(_ title: String, subtitle: String? = nil,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        let header = GlassPageHeader(title: title, subtitle: subtitle, trailing: trailing)
        return self
            .modifier(TopBar(bar: header))
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Mounts a custom top bar. On iOS 26 as a safe-area BAR, so the scroll view beneath knows it is
/// there and draws its own soft scroll-edge effect under it; on iOS 18 as a plain inset.
private struct TopBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0) { bar }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { bar }
        }
    }
}

/// The one legibility shade behind a top bar — the glass page header, Home's header once its hero
/// has scrolled away, the title page's bar once it scrolls. Held at `hold` down to the bar's
/// bottom edge, then faded to nothing over `fade` points below it.
///
/// Sized by its container (a header's background) — or, given `barHeight`, as an overlay over a
/// whole page: the top safe area plus that many points.
struct TopBarShade: View {
    var opacity: Double = 1
    var color: Color = Theme.Palette.shadeInk
    /// Nearly solid, measured: at 0.85–0.93 a white pill (Home's Resume) scrolling under the bar
    /// still read plainly through it on the iPhone 17 Pro simulator.
    var hold: Double = 0.97
    var fade: CGFloat = 24
    var barHeight: CGFloat?

    var body: some View {
        Group {
            if let barHeight {
                GeometryReader { geo in
                    stack.frame(height: geo.safeAreaInsets.top + barHeight + fade, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                }
            } else {
                stack.padding(.bottom, -fade)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stack: some View {
        VStack(spacing: 0) {
            color.opacity(hold * opacity)
            LinearGradient(colors: [color.opacity(hold * opacity), color.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
    }
}
