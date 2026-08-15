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
            } else if let preview = Self.uiPreview {
                #if DEBUG
                MagnetUIPreview(target: preview)   // -uiPreview <magnetidle|magnetready|…>
                #else
                RootView().environment(session)
                #endif
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

    /// The value after `-uiPreview` in the launch arguments, if any. DEBUG-only visual harnesses,
    /// same convention as SeretTV.
    private static var uiPreview: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
