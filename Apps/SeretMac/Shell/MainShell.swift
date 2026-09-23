import SwiftUI

/// The signed-in window: full-bleed page content under the floating sidebar. The page's leading edge
/// follows the sidebar's width on the same spring, so collapsing glides the whole page.
struct MainShell: View {
    @Bindable var model: ShellModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasBackground()
            SectionPlaceholder(section: model.selection)
                .id(model.selection)
                .transition(.opacity)
                .padding(.leading, SidebarMetrics.contentLeading(collapsed: model.isSidebarCollapsed))
                .padding(.trailing, 28)
            FloatingSidebar(model: model)
        }
        .background(TrafficLightsPlacement(origin: SidebarMetrics.trafficLightsOrigin))
        .animation(Theme.Motion.standard, value: model.isSidebarCollapsed)
        .animation(Theme.Motion.fade, value: model.selection)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 650)
        .focusedSceneValue(\.shellModel, model)
    }
}
