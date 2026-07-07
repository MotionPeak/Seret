import UIKit

/// Locks the iPhone to portrait for browsing and only opens up to landscape while the player is on
/// screen — the standard phone-media-app behaviour, and the fix for the browse/library/detail UI
/// looking broken when the phone is rotated. iPad is unaffected: it always allows all orientations
/// (the split view + grids adapt fine to landscape).
@MainActor
enum OrientationGate {
    /// True only while the player is presented, so the phone may rotate to landscape for video.
    private(set) static var playerActive = false

    /// The orientations UIKit is allowed to use right now.
    static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return playerActive ? .allButUpsideDown : .portrait
    }

    /// Enter/leave the player. Entering merely ALLOWS landscape (the viewer chooses to rotate);
    /// leaving forces the phone back to portrait so browsing is never left sideways.
    static func setPlayerActive(_ active: Bool) {
        playerActive = active
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let scene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if !active {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }
}

/// Routes UIKit's orientation query to `OrientationGate` (wired via `@UIApplicationDelegateAdaptor`).
final class SeretAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationGate.mask
    }
}
