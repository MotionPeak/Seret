import SwiftUI

/// The signed-in window: full-bleed page content under the floating sidebar. The page's leading edge
/// follows the sidebar's width on the same spring, so collapsing glides the whole page. Each section
/// is its own `NavigationStack`, and pages read their leading clearance from the environment instead
/// of the shell padding them — so later full-bleed art can run under the sidebar.
struct MainShell: View {
    @Bindable var model: ShellModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            SectionStack(section: model.selection, model: model)
                .id(model.selection)
                .transition(.opacity)
            FloatingSidebar(model: model)
            BackForwardCapsule(model: model)
        }
        .environment(\.pageLeadingInset, SidebarMetrics.contentLeading(collapsed: model.isSidebarCollapsed))
        .environment(model)
        .background(TrafficLightsPlacement(origin: SidebarMetrics.trafficLightsOrigin))
        .animation(Theme.Motion.standard, value: model.isSidebarCollapsed)
        .animation(Theme.Motion.fade, value: model.selection)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 650)
        .focusedSceneValue(\.shellModel, model)
    }
}
