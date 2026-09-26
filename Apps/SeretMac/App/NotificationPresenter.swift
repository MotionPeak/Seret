import UserNotifications

/// macOS hides a notification from the FOREGROUND app unless its delegate explicitly asks to show
/// it — without this, a "Ready to watch" download notification never appeared while Seret was the
/// app in front, which is exactly when it finishes.
@MainActor
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
