import SwiftUI

@main
struct SeretMacApp: App {
    private let launch = LaunchOptions.current

    var body: some Scene {
        WindowGroup {
            if launch.isRunningTests {
                Color.clear                     // hosting unit tests: no live UI, no network
            } else {
                #if DEBUG
                if let preview = launch.uiPreview {
                    UIPreviewRoot(target: preview)
                } else {
                    placeholder
                }
                #else
                placeholder
                #endif
            }
        }
    }

    private var placeholder: some View {
        Text("Seret").font(.largeTitle.bold()).frame(minWidth: 900, minHeight: 600)
    }
}
