import CoreGraphics
import DebridCore
import DebridUI
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

    // MARK: - Navigation

    private func item(_ id: String) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: "Title \(id)", year: 2024, sources: [], seasons: [])
    }
    private func route(_ id: String) -> AppRoute { .title(item(id)) }

    @Test func eachSectionKeepsItsOwnPath() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.movies)
        model.open(route("a"))
        model.select(.shows)
        model.open(route("b"))

        #expect(model.history(for: .movies).path == [route("a")])
        #expect(model.history(for: .shows).path == [route("b")])
    }

    @Test func reselectingTheCurrentSectionPopsToRoot() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        #expect(model.history(for: .library).path == [route("a")])

        model.select(.library)                     // already selected: pop to root
        #expect(model.selection == .library)
        #expect(model.history(for: .library).path.isEmpty)
    }

    @Test func openPushesOnTheSelectedSection() {
        let model = ShellModel(defaults: freshDefaults())
        model.select(.library)
        model.open(route("a"))
        #expect(model.history(for: .library).path == [route("a")])
        #expect(model.canGoBack)
    }

    // MARK: - Playback slot

    private func request(_ id: String) -> PlaybackRequest {
        let source = MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                                 parsed: ParsedRelease(title: "t"))
        return PlaybackRequest(item: item(id), source: source, resumeAt: nil, label: "t", contentKey: id)
    }

    @Test func endingPlaybackClearsTheSlotAndOnlyTeardownSignalsPages() {
        let model = ShellModel(defaults: freshDefaults())
        model.present(request("a"))
        #expect(model.playback != nil)

        model.endPlayback()
        #expect(model.playback == nil)
        // Pages must not re-read watch state yet: the final position is still being written.
        #expect(model.playbackEndedCount == 0)

        model.playerDidTearDown()
        #expect(model.playbackEndedCount == 1)
    }

    @Test func presentingReplacesAnEarlierPresentation() {
        let model = ShellModel(defaults: freshDefaults())
        model.present(request("a"))
        let firstID = model.playback?.id
        model.present(request("a"))
        #expect(model.playback?.id != firstID)
    }

    // MARK: - Toast

    @Test func aNewToastReplacesTheOld() {
        let model = ShellModel(defaults: freshDefaults())
        model.showToast("First")
        let firstID = model.toast?.id
        model.showToast("Second", isFailure: true)

        #expect(model.toast?.id != firstID)
        #expect(model.toast?.message == "Second")
        #expect(model.toast?.isFailure == true)
    }

    @Test func dismissingAStaleToastKeepsTheNewOne() {
        let model = ShellModel(defaults: freshDefaults())
        model.showToast("First")
        let staleID = model.toast!.id
        model.showToast("Second")

        model.dismissToast(staleID)

        #expect(model.toast?.message == "Second")
    }
}
