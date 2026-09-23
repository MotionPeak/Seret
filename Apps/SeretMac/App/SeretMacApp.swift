import DebridCore
import DebridUI
import SwiftUI

@main
struct SeretMacApp: App {
    private let launch = LaunchOptions.current
    @State private var session = AppSession(realDebrid: RealDebridSession(store: KeychainTokenStore()))

    init() {
        // Posters and stills are fetched over and over while browsing; a larger URL cache keeps the
        // compressed bytes on disk (the decoded bitmaps live in ImageMemoryCache).
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            if launch.isRunningTests {
                Color.clear                     // hosting unit tests: no live UI, no network
            } else {
                #if DEBUG
                if let preview = launch.uiPreview {
                    UIPreviewRoot(target: preview)
                } else {
                    RootView().environment(session)
                }
                #else
                RootView().environment(session)
                #endif
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1440, height: 900)
        .commands { SeretCommands(session: session) }

        Settings {
            SettingsRoot().environment(session)
        }
    }
}
