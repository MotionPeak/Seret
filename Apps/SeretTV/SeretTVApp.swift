import DebridCore
import DebridUI
import SwiftUI

@main
struct SeretTVApp: App {
    @State private var session = AppSession(
        realDebrid: RealDebridSession(store: KeychainTokenStore()))

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                // The app launches as the unit-test host; don't drive the live
                // (network-firing) sign-in UI during tests.
                Color.clear
            } else {
                RootView()
                    .environment(session)
            }
        }
    }

    /// Xcode sets this env var in the host process during `xcodebuild test`
    /// (true for both XCTest and Swift Testing runs).
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
