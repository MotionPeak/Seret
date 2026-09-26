import DebridCore
import Testing
@testable import Seret

@Suite struct NavigationHistoryTests {
    private func item(_ id: String) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: "Title \(id)", year: 2024, sources: [], seasons: [])
    }
    private func route(_ id: String) -> AppRoute { .title(item(id)) }

    @Test func pushAppendsAndClearsForward() {
        var history = NavigationHistory()
        history.push(route("a"))
        history.back()
        #expect(history.canGoForward)

        history.push(route("b"))
        #expect(history.path == [route("b")])
        #expect(!history.canGoForward)
    }

    @Test func backThenForwardReturnsToTheSamePage() {
        var history = NavigationHistory()
        history.push(route("a"))
        history.push(route("b"))
        let original = history.path

        history.back()
        #expect(history.path == [route("a")])
        history.forward()
        #expect(history.path == original)
    }

    @Test func backAtTheRootDoesNothing() {
        var history = NavigationHistory()
        history.back()
        #expect(history.path.isEmpty)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func aSystemPopIsRememberedForForward() {
        var history = NavigationHistory()
        history.push(route("a"))
        history.push(route("b"))
        history.push(route("c"))
        let original = history.path

        history.setPath([route("a")])           // the system popped two at once
        #expect(history.canGoForward)

        history.forward()
        history.forward()
        #expect(history.path == original)
    }

    @Test func aDifferentPathIsANewNavigation() {
        var history = NavigationHistory()
        history.push(route("a"))
        history.back()
        #expect(history.canGoForward)

        history.setPath([route("z")])            // not a prefix of the old path
        #expect(!history.canGoForward)
        #expect(history.path == [route("z")])
    }

    @Test func popToRootForgetsForward() {
        var history = NavigationHistory()
        history.push(route("a"))
        history.push(route("b"))
        history.back()
        #expect(history.canGoForward)

        history.popToRoot()
        #expect(history.path.isEmpty)
        #expect(!history.canGoForward)
    }
}
