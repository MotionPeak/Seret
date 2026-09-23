import CoreGraphics
import SwiftUI

/// Mockup 3's pointer tilt: pitch and yaw toward the pointer, plus where the glare highlight sits.
/// Pure so the maths can be unit-tested without measuring a real layout.
///
/// `location` is the pointer's position in the POSTER's own coordinates (the title/caption below
/// it are not part of this space) — outside the poster's bounds clamps to its nearest edge, and a
/// zero-sized poster reports flat rather than dividing by zero.
struct PosterTilt: Equatable {
    /// Degrees of rotation about the X axis, ±8 at the poster's top/bottom edge.
    let pitch: Double
    /// Degrees of rotation about the Y axis, ±9 at the poster's left/right edge.
    let yaw: Double
    /// Where the glare highlight is centred, in the poster's own unit space.
    let glare: UnitPoint

    static let flat = PosterTilt(pitch: 0, yaw: 0, glare: .center)

    private init(pitch: Double, yaw: Double, glare: UnitPoint) {
        self.pitch = pitch
        self.yaw = yaw
        self.glare = glare
    }

    init(location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { self = .flat; return }
        let x = min(1, max(0, location.x / size.width))
        let y = min(1, max(0, location.y / size.height))
        pitch = (0.5 - y) * 16
        yaw = (x - 0.5) * 18
        glare = UnitPoint(x: x, y: y)
    }
}
