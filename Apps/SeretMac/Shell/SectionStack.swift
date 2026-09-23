import DebridCore
import SwiftUI

extension EnvironmentValues {
    /// How far a page's own leading content (not full-bleed art) clears the floating sidebar.
    /// `MainShell` sets it from `SidebarMetrics.contentLeading`; a page pads itself by it instead
    /// of the shell padding the page, so full-bleed art (the title-page hero, later) can run under
    /// the sidebar while text and grids do not.
    @Entry var pageLeadingInset: CGFloat = 0
}

/// One sidebar section's own `NavigationStack`, backed by its `ShellModel`-held `NavigationHistory`
/// (push/pop both directions — `NavigationStack` on its own can only pop).
struct SectionStack: View {
    let section: SidebarSection
    @Bindable var model: ShellModel

    private var path: Binding<[AppRoute]> {
        Binding(get: { model.history(for: section).path },
                set: { model.setPath($0, for: section) })
    }

    var body: some View {
        NavigationStack(path: path) {
            // The section root. M2/M4 swap this per-section (My Library lands in Task 4); every
            // other section stays this placeholder until its own phase.
            SectionPlaceholder(section: section)
                .navigationDestination(for: AppRoute.self) { route in
                    RouteView(route: route)
                        .navigationBarBackButtonHidden(true)
                }
        }
    }
}

/// Renders whatever a pushed route resolves to. `.title` is a stand-in until Task 5 builds the
/// real title page.
private struct RouteView: View {
    let route: AppRoute
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        switch route {
        case .title(let item):
            Text(item.title)
                .font(Theme.Typo.titleXL())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 54)
                .padding(.leading, pageLeadingInset)
                .padding(.trailing, 28)
        }
    }
}
