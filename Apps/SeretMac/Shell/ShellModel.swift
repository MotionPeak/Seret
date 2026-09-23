import Foundation
import Observation

/// One window's shell state: which section is showing and whether the sidebar is a rail.
/// Collapsing is remembered across launches.
@MainActor
@Observable
final class ShellModel {
    var selection: SidebarSection = .home
    private(set) var isSidebarCollapsed: Bool

    @ObservationIgnored private let defaults: UserDefaults
    private static let collapsedKey = "seret.mac.sidebarCollapsed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSidebarCollapsed = defaults.bool(forKey: Self.collapsedKey)
    }

    func toggleSidebar() {
        isSidebarCollapsed.toggle()
        defaults.set(isSidebarCollapsed, forKey: Self.collapsedKey)
    }

    func select(_ section: SidebarSection) { selection = section }

    /// ⌘1…⌘5. A digit with no section is ignored.
    func select(shortcut digit: Int) {
        guard let section = SidebarSection.allCases.first(where: { $0.shortcutDigit == digit }) else { return }
        selection = section
    }
}
