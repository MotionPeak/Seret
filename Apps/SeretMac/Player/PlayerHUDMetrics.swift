import CoreGraphics

/// The windowed HUD's geometry, in points, measured against mockup 4's 12 pt cap. The HUD is sized
/// in points and never scales with the window — only the bottom panel's WIDTH tracks the window,
/// clamped to `panelMaxWidth`.
enum PlayerHUDMetrics {
    static let panelMaxWidth: CGFloat = 912
    static let sideMargin: CGFloat = 24
    static let panelBottom: CGFloat = 26
    static let panelCorner: CGFloat = 26
    static let iconButton: CGFloat = 35
    static let playButton: CGFloat = 50
    static let icon: CGFloat = 18
    static let playIcon: CGFloat = 27
    static let topBarTop: CGFloat = 24
    /// Clears the traffic lights, which live inside the (now-hidden) sidebar's corner.
    static let topBarLeadingWindowed: CGFloat = 92
    static let topBarLeadingFullScreen: CGFloat = 26
    static let tracksPanelWidth: CGFloat = 340
    /// Bottom inset for anything stacked on the right above the transport panel (the tracks panel,
    /// Up Next): the panel is up to 912 pt wide and centred, so in a 1440 pt window its trailing
    /// end runs under a 340 pt right-hand column unless that column stops above it. Panel: 26 pt
    /// off the bottom + ~128 pt tall (measured) + a 16 pt gap.
    static let clearOfBottomPanel: CGFloat = 170

    static func panelWidth(windowWidth: CGFloat) -> CGFloat {
        max(0, min(panelMaxWidth, windowWidth - 2 * sideMargin))
    }

    /// Full screen hides sooner than windowed — spec §7.2: ≈2.9 s windowed, ≈1.8 s full screen.
    static func autoHideDelay(isFullScreen: Bool) -> Duration {
        isFullScreen ? .seconds(1.8) : .seconds(2.9)
    }

    /// Full screen's compact single-row "cinema" bar (mockup 4's `.mini`), derived from its 10 pt
    /// unit (`--h` in the mockup's `.pwin.fs` rule) rather than the windowed panel's values — the
    /// windowed two-row panel must never be shown in full screen.
    enum FullScreen {
        private static let unit: CGFloat = 10

        static let barMaxWidth: CGFloat = unit * 70       // 700
        static let barBottom: CGFloat = unit * 2.4        // 24
        static let barPaddingV: CGFloat = unit * 0.45     // 4.5
        static let barPaddingH: CGFloat = unit * 0.9      // 9
        static let barGap: CGFloat = unit * 0.45          // 4.5
        static let sideMargin: CGFloat = unit * 2         // 20

        static let iconButton: CGFloat = unit * 3         // 30
        static let icon: CGFloat = unit * 1.45            // 14.5
        static let playButton: CGFloat = unit * 3.3       // 33
        static let playIcon: CGFloat = unit * 1.75        // 17.5
        static let scrubHeight: CGFloat = unit * 2        // 20
        static let timeFont: CGFloat = unit * 1.15        // 11.5
        static let timeMinWidth: CGFloat = unit * 5        // 50
        static let separatorHeight: CGFloat = unit * 1.7   // 17

        static let topBarTop: CGFloat = unit * 1.8         // 18
        static let topBarGap: CGFloat = unit * 0.9         // 9
        static let titleFont: CGFloat = unit * 1.4         // 14
        static let chipFont: CGFloat = unit * 0.85         // 8.5

        /// Fraction of the picture's height covered by each scrim, and its peak opacity — both
        /// lighter and shorter than windowed's (0.26/0.66 top, 0.42/0.78 bottom).
        static let scrimTopFraction: CGFloat = 0.13
        static let scrimTopOpacity: Double = 0.4
        static let scrimBottomFraction: CGFloat = 0.17
        static let scrimBottomOpacity: Double = 0.42

        /// The bar's own height (padding + its tallest control) plus its bottom offset and a small
        /// gap — anything stacked above it (the tracks panel, Up Next) must clear this, not
        /// `clearOfBottomPanel`, which is windowed-panel-sized and far too tall here.
        static let clearOfBar: CGFloat = barBottom + (barPaddingV * 2 + playButton) + 16

        static func barWidth(windowWidth: CGFloat) -> CGFloat {
            max(0, min(barMaxWidth, windowWidth - 2 * sideMargin))
        }
    }
}

/// Which HUD chrome is on screen — windowed's two-row panel, or full screen's compact single-row
/// bar (spec §7.2). `PlayerHUD` reads this once per render instead of branching on
/// `windowRef.isFullScreen` at every call site.
enum PlayerHUDStyle {
    case windowed
    case fullScreen

    static func current(isFullScreen: Bool) -> PlayerHUDStyle {
        isFullScreen ? .fullScreen : .windowed
    }
}
