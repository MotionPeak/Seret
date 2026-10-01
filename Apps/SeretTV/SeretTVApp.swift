import DebridCore
import DebridUI
import SwiftUI

@main
struct SeretTVApp: App {
    @State private var session = AppSession(
        realDebrid: RealDebridSession(store: KeychainTokenStore()))

    init() {
        // The stream cache's lines go into vlc.log beside libvlc's own (see DiagnosticsLog).
        AppSession.streamDiagnostics = { DiagnosticsLog.shared.write($0) }
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
            } else if let preview = Self.uiPreview {
                #if DEBUG
                PlayerUIPreview(target: preview)   // -uiPreview <scrubbar|settings|subtitles>
                #else
                RootView().environment(session)
                #endif
            } else {
                #if DEBUG
                // The harness is attached ONLY when the flag is present. Attaching it
                // unconditionally would hijack every debug launch into playback.
                // `-autoPlayShow` / `-autoPlayMovie <title>` imply auto-play, so they work without
                // `-autoPlay 0`.
                if let index = AutoPlayHarness.launchIndex {
                    RootView()
                        .environment(session)
                        .modifier(AutoPlayHarness(session: session, index: index))
                } else {
                    RootView().environment(session)
                }
                #else
                RootView()
                    .environment(session)
                #endif
            }
        }
    }

    /// Xcode sets this env var in the host process during `xcodebuild test`
    /// (true for both XCTest and Swift Testing runs).
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The value after `-uiPreview` in the launch arguments, if any. DEBUG-only visual harnesses.
    private static var uiPreview: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
