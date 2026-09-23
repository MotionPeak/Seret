import DebridUI
import SwiftUI

/// The signed-in window: full-bleed page content under the floating sidebar. The page's leading edge
/// follows the sidebar's width on the same spring, so collapsing glides the whole page. Each section
/// is its own `NavigationStack`, and pages read their leading clearance from the environment instead
/// of the shell padding them — so later full-bleed art can run under the sidebar.
///
/// Playback is an overlay layer, not a cover or a second window: the section content underneath
/// stays mounted (opacity 0, no hit testing, hidden from accessibility) so the title page keeps its
/// scroll position, and `.id(presentation.id)` guarantees one `PlayerHost` per presentation.
struct MainShell: View {
    @Bindable var model: ShellModel
    @Environment(AppSession.self) private var session: AppSession?

    var body: some View {
        ZStack {
            shellContent
                .opacity(model.playback == nil ? 1 : 0)
                .allowsHitTesting(model.playback == nil)
                .accessibilityHidden(model.playback != nil)
            if let playback = model.playback, let session {
                PlayerHost(request: playback.request, app: session, onExit: { model.endPlayback() })
                    .id(playback.id)          // a new presentation is a new host
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(Theme.Motion.fade, value: model.playback?.id)
        .environment(\.pageLeadingInset, SidebarMetrics.contentLeading(collapsed: model.isSidebarCollapsed))
        .environment(model)
        .background(TrafficLightsPlacement(origin: SidebarMetrics.trafficLightsOrigin))
        .animation(Theme.Motion.standard, value: model.isSidebarCollapsed)
        .animation(Theme.Motion.fade, value: model.selection)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 650)
        .focusedSceneValue(\.shellModel, model)
    }

    private var shellContent: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            SectionStack(section: model.selection, model: model)
                .id(model.selection)
                .transition(.opacity)
            FloatingSidebar(model: model)
            BackForwardCapsule(model: model)
        }
    }
}
