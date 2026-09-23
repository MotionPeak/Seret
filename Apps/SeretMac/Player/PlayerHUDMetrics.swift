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
}
