import SwiftUI

/// One cohesive tvOS type ramp. Every screen routes its text through these roles, so the
/// hierarchy (size · weight · tracking) lives in one place instead of ~140 ad-hoc `.system(size:)`
/// calls. Tuned for the 10-foot viewing distance; big titles get a hair of negative-to-tight
/// tracking so they read "designed", small overlines get wide tracking + caps.
extension Theme {
    enum Typography {
        static let displaySize: CGFloat = 64   // centered full-screen hero ("Who's Watching?")
        static let heroSize:    CGFloat = 52   // Home featured hero title
        static let h1Size:      CGFloat = 48   // screen / detail titles
        static let h2Size:      CGFloat = 44   // section & rail headers (≈ the original .title2)
        static let cardSize:    CGFloat = 28   // poster / episode captions, list rows
        static let bodySize:    CGFloat = 29   // overviews, descriptions
        static let calloutSize: CGFloat = 25
        static let captionSize: CGFloat = 21   // chips, sublabels, overlines
        static let microSize:   CGFloat = 18   // dense meta (ratings digits)
    }
}

extension Theme {
    /// Shared layout metrics so margins/rounding match across every screen ("flushed").
    enum Layout {
        /// Standard horizontal content inset (tvOS overscan-safe).
        static let contentMargin: CGFloat = 60
        /// Poster / card corner radius — a touch softer than the cross-platform token for the tvOS look.
        static let posterCorner: CGFloat = 12
    }
}

extension Font {
    /// Seret system-font factory — keeps weight/design consistent at every call site.
    static func seret(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Centered full-screen hero ("Who's Watching?", "Add Profile").
    func displayTitle() -> some View { font(.seret(Theme.Typography.displaySize, .heavy)).tracking(0.5) }
    /// Home featured hero title.
    func heroTitle() -> some View { font(.seret(Theme.Typography.heroSize, .heavy)).tracking(0.5) }
    /// Screen / detail H1 (movie & show titles, Add title, Settings).
    func screenTitle() -> some View { font(.seret(Theme.Typography.h1Size, .bold)).tracking(0.4) }
    /// Section & horizontal-rail headers ("Continue Watching", "Drama", "Versions").
    func sectionTitle() -> some View { font(.seret(Theme.Typography.h2Size, .bold)).tracking(0.3) }
    /// Poster captions, episode titles, list-row titles.
    func cardTitle() -> some View { font(.seret(Theme.Typography.cardSize, .semibold)) }
    /// Body copy — overviews & descriptions, with comfortable line spacing.
    func bodyText() -> some View { font(.seret(Theme.Typography.bodySize, .regular)).lineSpacing(4) }
    /// Secondary callout text (helper lines, status).
    func calloutText() -> some View { font(.seret(Theme.Typography.calloutSize, .regular)) }
    /// Gold uppercase overline (e.g. the "Continue Watching" eyebrow over the hero).
    func eyebrow() -> some View { font(.seret(Theme.Typography.captionSize, .semibold)).tracking(2).textCase(.uppercase) }
}
