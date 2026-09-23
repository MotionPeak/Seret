import CoreGraphics
import Foundation
import Testing
@testable import Seret

@MainActor
@Suite struct ShellModelTests {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "seret.tests.\(UUID().uuidString)")! }

    @Test func startsOnHomeWithTheSidebarOpen() {
        let model = ShellModel(defaults: freshDefaults())
        #expect(model.selection == .home)
        #expect(model.isSidebarCollapsed == false)
    }

    @Test func collapsingIsRememberedAcrossLaunches() {
        let defaults = freshDefaults()
        let first = ShellModel(defaults: defaults)
        first.toggleSidebar()
        #expect(first.isSidebarCollapsed)
        #expect(ShellModel(defaults: defaults).isSidebarCollapsed)
    }

    @Test func commandDigitsSelectSectionsInSidebarOrder() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(shortcut: 3)
        #expect(model.selection == .shows)
        model.select(shortcut: 5)
        #expect(model.selection == .library)
        model.select(shortcut: 9)                       // no such section: nothing changes
        #expect(model.selection == .library)
    }

    @Test func theSidebarIsGroupedBrowseThenYours() {
        #expect(SidebarSection.allCases.filter { $0.group == .browse } == [.home, .movies, .shows])
        #expect(SidebarSection.allCases.filter { $0.group == .yours } == [.watchlist, .library])
        #expect(SidebarSection.allCases.map(\.shortcutDigit) == [1, 2, 3, 4, 5])
    }

    // The literal RHS is cast to CGFloat explicitly: `#expect(cgFloat == 10 + 250 + 14)` mistypes the
    // right operand under this toolchain's Swift Testing macro expansion and fails even though the
    // values are equal (confirmed with a plain `==` outside the macro) — CGFloat(...) sidesteps it.
    @Test func contentStartsBesideTheSidebarInBothStates() {
        #expect(SidebarMetrics.contentLeading(collapsed: false) == CGFloat(10 + 250 + 14))
        #expect(SidebarMetrics.contentLeading(collapsed: true) == CGFloat(10 + 76 + 14))
    }
}
