#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only harness for the signed-in shell: the real `MainShell` (tab bar on iPhone, floating
/// sidebar on iPad) on a session that never signs in, so the chrome can be screenshotted on a
/// simulator with no Real-Debrid account. Pages show their loading states; the point is the shell.
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview shell
///         [-shellSection home|movies|shows|watchlist|library|search]
///         [-seret.ipad.sidebarExpanded NO]     # the collapsed iPad sidebar
///         [-glassFallback]                     # the iOS 18 glass look, on an iOS 26 simulator
///
/// `-uiPreview glass` shows the glass toolkit alone over a busy picture, for judging the glass
/// itself (and, with `-glassFallback`, its iOS 18 stand-in).
///
/// Nothing here fires a network request: the session is never resolved, so it has no stores.
struct ShellUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var router: AppRouter = {
        let router = AppRouter()
        router.selectedSection = ShellUIPreview.argument("-shellSection").flatMap(MainShell.Section.init) ?? .home
        return router
    }()

    var body: some View {
        Group {
            if target == "glass" {
                GlassGalleryPreview()
            } else {
                MainShell()
                    .environment(session)
                    .environment(router)
                    .environment(TileWatchMarks.placeholder)
                    .environment(WatchlistMarks.placeholder)
            }
        }
        .preferredColorScheme(.dark)
    }

    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

/// Every glass control on a busy, colourful backdrop — glass is only judgeable over a picture.
private struct GlassGalleryPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x5F7F6E), Color(hex: 0x2B3A44), Theme.Palette.canvas],
                           startPoint: .top, endPoint: .bottom)
                .overlay {
                    // Stripes so the blur has something to bend.
                    HStack(spacing: 18) {
                        ForEach(0..<14, id: \.self) { i in
                            Rectangle().fill(i.isMultiple(of: 2) ? Color.white.opacity(0.25) : .clear)
                        }
                    }
                    .rotationEffect(.degrees(18))
                    .scaleEffect(1.6)
                }
                .ignoresSafeArea()
            VStack(spacing: 28) {
                GlassPageHeader(title: "Seret") {
                    GlassCircleButton(systemImage: "magnifyingglass", label: "Search") {}
                    GlassCircleButton(systemImage: "gearshape", label: "Settings") {}
                }
                Spacer()
                HStack(spacing: 14) {
                    PrimaryPill(title: "Resume", systemImage: "play.fill") {}
                    GlassGroup {
                        HStack(spacing: 14) {
                            GlassCircleButton(systemImage: "plus", label: "Add") {}
                            GlassCircleButton(systemImage: "ellipsis", label: "More") {}
                        }
                    }
                }
                GlassGroup {
                    HStack(spacing: 10) {
                        GlassPill(title: "Subtitles", systemImage: "captions.bubble") {}
                        GlassPill(title: "Audio", systemImage: "waveform") {}
                        GlassPill(title: "1×") {}
                    }
                }
                ProgressLine(fraction: 0.42).frame(width: 220)
                Spacer()
            }
        }
    }
}
#endif
