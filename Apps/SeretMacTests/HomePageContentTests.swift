import DebridCore
import Testing
@testable import DebridUI
@testable import Seret

@Suite struct HomePageContentTests {
    @Test func anythingToShowIsContentEvenMidLoad() {
        #expect(HomePageContent.make(library: .loading, continueWatching: 1, recentlyAdded: 0, downloading: 0) == .content)
        #expect(HomePageContent.make(library: .loading, continueWatching: 0, recentlyAdded: 3, downloading: 0) == .content)
        #expect(HomePageContent.make(library: nil, continueWatching: 0, recentlyAdded: 0, downloading: 1) == .content)
    }

    @Test func nothingWhileTheFirstLoadRunsIsASkeleton() {
        #expect(HomePageContent.make(library: nil, continueWatching: 0, recentlyAdded: 0, downloading: 0) == .skeleton)
        #expect(HomePageContent.make(library: .loading, continueWatching: 0, recentlyAdded: 0, downloading: 0) == .skeleton)
    }

    @Test func anEmptyLibraryIsTheEmptyState() {
        #expect(HomePageContent.make(library: .empty, continueWatching: 0, recentlyAdded: 0, downloading: 0) == .empty)
        #expect(HomePageContent.make(library: .loaded, continueWatching: 0, recentlyAdded: 0, downloading: 0) == .empty)
    }

    @Test func aFailedLoadWithNothingCachedSaysWhy() {
        #expect(HomePageContent.make(library: .failed("x"), continueWatching: 0, recentlyAdded: 0, downloading: 0) == .failed("x"))
    }

    @Test func aFilmSaysHowMuchIsLeft() {
        let text = ContinueCaption.caption(kind: .movie, subtitle: "", resumeAt: 3753, fraction: 3753 / 8160)
        #expect(text == "1h 13m left")
    }

    @Test func underAnHourIsMinutes() {
        let text = ContinueCaption.caption(kind: .movie, subtitle: "", resumeAt: 100, fraction: 100 / 2600)
        #expect(text == "42 min left")
    }

    @Test func theLastMinuteIsAlmostDone() {
        let text = ContinueCaption.caption(kind: .movie, subtitle: "", resumeAt: 8100, fraction: 8100 / 8150)
        #expect(text == "Almost done")
    }

    @Test func anEpisodeNamesItself() {
        let caption = ContinueCaption.caption(kind: .show, subtitle: "S1 \u{00B7} E3", resumeAt: 1210, fraction: 0.5)
        #expect(caption == "S1 \u{00B7} E3")
        let eyebrow = ContinueCaption.eyebrow(kind: .show, subtitle: "S1 \u{00B7} E3", resumeAt: 1210, fraction: 0.5)
        #expect(eyebrow == "Continue \u{00B7} S1 \u{00B7} E3")
    }

    @Test func noPositionSaysNothing() {
        #expect(ContinueCaption.caption(kind: .movie, subtitle: "", resumeAt: nil, fraction: 0.5).isEmpty)
        #expect(ContinueCaption.caption(kind: .movie, subtitle: "", resumeAt: 100, fraction: 0).isEmpty)
    }

    @Test func theEyebrowFallsBackToContinueWatching() {
        #expect(ContinueCaption.eyebrow(kind: .movie, subtitle: "", resumeAt: nil, fraction: 0) == "Continue Watching")
    }
}
