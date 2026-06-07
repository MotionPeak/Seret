import Foundation
import UserNotifications

/// Fires a local notification when a requested download finishes. Foreground delivery (the app is
/// running and `DownloadMonitor` detects completion); background delivery is Slice 3. No-op until
/// the user grants permission, so it's always safe to call.
///
/// iOS/iPadOS only: tvOS's `UNMutableNotificationContent` exposes no title/body/sound, so there is
/// no useful local "ready" alert on the TV — these methods are no-ops there (the title still flips
/// into the library via the library refresh).
@MainActor
public final class DownloadNotifier {
    private var authorized = false

    public init() {}

    /// Ask once for permission to post "ready" notifications. Silently records denial.
    public func requestAuthorization() async {
        #if os(iOS)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        authorized = granted
        #endif
    }

    /// Post "<title> finished downloading." immediately. No-op if unauthorized or on tvOS.
    public func notifyReady(title: String) {
        #if os(iOS)
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ready to watch"
        content.body = "\(title) finished downloading."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        #endif
    }
}
