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

    static func panelWidth(windowWidth: CGFloat) -> CGFloat {
        max(0, min(panelMaxWidth, windowWidth - 2 * sideMargin))
    }
}
