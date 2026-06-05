import DebridCore
import DebridUI
import SwiftUI

@main
struct SeretTVApp: App {
    @State private var session = AppSession(
        realDebrid: RealDebridSession(store: KeychainTokenStore()))

    init() {
        // Generous shared image cache — TMDB posters/backdrops/episode stills are small
        // and reused across launches. AsyncImage uses URLSession.shared which honors this.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,      // 64 MB in RAM
            diskCapacity: 512 * 1024 * 1024,       // 512 MB on disk (persists across launches)
            directory: nil)
    }

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
