import SwiftUI
import UIKit

/// One cohesive tvOS type ramp. Every screen routes its text through these roles, so the
/// hierarchy (size · weight · tracking) lives in one place instead of ~140 ad-hoc `.system(size:)`
/// calls. Tuned for the 10-foot viewing distance; big titles get a hair of negative-to-tight
/// tracking so they read "designed", small overlines get wide tracking + caps.
extension Theme {
    enum Typography {
        static let displaySize: CGFloat = 64   // centered full-screen hero ("Who's Watching?")
        static let heroSize:    CGFloat = 52   // Home featured hero title
        static let h1Size:      CGFloat = 48   // screen / detail titles
        static let h2Size:      CGFloat = 34   // section & rail headers
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

extension Theme.Typography {
    /// The tvOS point size of a system text style, read from UIKit rather than hard-coded, so the
    /// style-based factory below keeps every existing size exactly.
    static func size(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).pointSize
    }
}

extension Font {
    /// Seret type factory — SF Pro (the system font) at an explicit size and weight.
    ///
    /// Every UI string routes through here, so the face is a one-line decision. It is the system
    /// font because that is near-identical to Plex's face and falls back cleanly for Hebrew
    /// titles. Rubik is still bundled, but only for subtitle rendering (VLCKit's freetype).
    ///
    /// Keep `.system(size:)` on every `Image(systemName:)` rather than this, so symbol sizing
    /// stays independent of whatever face the UI text uses.
    static func seret(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// The system font at a system text style's point size, in an explicit weight — the
    /// replacement for the old "style dot weight" call sites, which the plain style constants below
    /// can't express. Note SwiftUI's `.caption`/`.title` are UIKit's `.caption1`/`.title1`.
    static func seret(_ style: UIFont.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .seret(Theme.Typography.size(style), weight)
    }

    // Stand-ins for the system text styles, at the SAME point sizes tvOS uses, with Seret's weights.
    static let seretTitle    = Font.seret(Theme.Typography.size(.title1), .bold)
    static let seretTitle2   = Font.seret(Theme.Typography.size(.title2), .semibold)
    static let seretTitle3   = Font.seret(Theme.Typography.size(.title3))
    static let seretHeadline = Font.seret(Theme.Typography.size(.headline), .semibold)
    static let seretBody     = Font.seret(Theme.Typography.size(.body))
    static let seretCallout  = Font.seret(Theme.Typography.size(.callout))
    static let seretCaption  = Font.seret(Theme.Typography.size(.caption1))
    static let seretCaption2 = Font.seret(Theme.Typography.size(.caption2))
}

extension View {
    /// Centered full-screen hero ("Who's Watching?", "Add Profile").
    func displayTitle() -> some View { font(.seret(Theme.Typography.displaySize, .heavy)).tracking(0.5) }
    /// Home featured hero title.
    func heroTitle() -> some View { font(.seret(Theme.Typography.heroSize, .heavy)).tracking(0.5) }
    /// Screen / detail H1 (movie & show titles, Add title, Settings).
    func screenTitle() -> some View { font(.seret(Theme.Typography.h1Size, .bold)).tracking(0.4) }
    /// Section & horizontal-rail headers ("Continue Watching", "Drama", "Versions").
    func sectionTitle() -> some View { font(.seret(Theme.Typography.h2Size, .semibold)).tracking(0) }
    /// Poster captions, episode titles, list-row titles.
    func cardTitle() -> some View { font(.seret(Theme.Typography.cardSize, .semibold)) }
    /// Side-menu row label.
    func navLabel() -> some View { font(.seret(30, .medium)) }
    /// Body copy — overviews & descriptions, with comfortable line spacing.
    func bodyText() -> some View { font(.seret(Theme.Typography.bodySize, .regular)).lineSpacing(4) }
    /// Secondary callout text (helper lines, status).
    func calloutText() -> some View { font(.seret(Theme.Typography.calloutSize, .regular)) }
    /// Uppercase overline (e.g. the "Continue Watching" eyebrow over the hero).
    func eyebrow() -> some View { font(.seret(Theme.Typography.captionSize, .semibold)).tracking(2).textCase(.uppercase) }
}
