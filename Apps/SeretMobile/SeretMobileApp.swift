import DebridCore
import DebridUI
import SwiftUI

@main
struct SeretMobileApp: App {
    @UIApplicationDelegateAdaptor(SeretAppDelegate.self) private var appDelegate
    @State private var session = AppSession(
        realDebrid: RealDebridSession(store: KeychainTokenStore()))

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                // The app hosts the unit tests; don't drive the live (network-firing) UI.
                Color.clear
            } else {
                RootView()
                    .environment(session)
            }
        }
    }

    /// Xcode sets this in the host process during `xcodebuild test`.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
