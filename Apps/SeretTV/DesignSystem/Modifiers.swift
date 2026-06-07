import SwiftUI

extension View {
    /// Soft gold bloom behind a view. A `radius` of 0 disables it.
    func goldGlow(_ radius: CGFloat, opacity: Double = 0.5) -> some View {
        shadow(color: Theme.Palette.gold.opacity(radius > 0 ? opacity : 0), radius: radius)
    }
}
