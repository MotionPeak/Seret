import CoreGraphics
import Testing
@testable import Seret

@Suite struct TrafficLightsLayoutTests {
    /// AppKit's own frames for a hidden-title-bar window, in the title bar's bottom-up coordinates.
    private let appKit = [CGRect(x: 9, y: 9, width: 14, height: 14),
                          CGRect(x: 32, y: 9, width: 14, height: 14),
                          CGRect(x: 55, y: 9, width: 14, height: 14)]

    @Test func theCloseButtonLandsAtTheOriginMeasuredFromTheWindowTop() {
        let moved = TrafficLightsLayout.frames(for: appKit, containerHeight: 40, origin: CGPoint(x: 18, y: 18))
        #expect(moved[0].minX == 18)
        #expect(40 - moved[0].maxY == 18)                 // 18 pt below the window's top edge
    }

    @Test func allThreeMoveTogetherKeepingAppKitsSpacing() {
        let moved = TrafficLightsLayout.frames(for: appKit, containerHeight: 40, origin: CGPoint(x: 18, y: 18))
        #expect(moved.map(\.minX) == [18, 41, 64])
        #expect(Set(moved.map(\.minY)).count == 1)
        #expect(moved.map(\.size) == appKit.map(\.size))
        #expect(TrafficLightsLayout.frames(for: [], containerHeight: 40, origin: .zero).isEmpty)
    }

    /// The buttons span ≈ 60 pt; they must sit inside the sidebar in its narrowest (rail) state too.
    @Test func theLightsFitInsideTheRail() {
        let origin = SidebarMetrics.trafficLightsOrigin
        #expect(origin.x > SidebarMetrics.inset && origin.y > SidebarMetrics.inset)
        #expect(origin.x + 60 <= SidebarMetrics.inset + SidebarMetrics.railWidth)
        #expect(origin.y + 14 < SidebarMetrics.inset + SidebarMetrics.trafficLightsBand)
    }
}
