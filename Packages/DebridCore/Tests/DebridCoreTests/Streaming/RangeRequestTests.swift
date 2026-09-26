import Testing
@testable import DebridCore

@Suite struct RangeRequestTests {
    @Test func noHeaderMeansTheWholeFile() {
        #expect(RangeRequest.parse(nil) == .whole)
        #expect(RangeRequest.parse("  ") == .whole)
    }

    @Test func openEndedIsWhatLibvlcSends() {
        // Every request in the iPad's vlc.log has this form.
        #expect(RangeRequest.parse("bytes=63960982350-") == .from(63_960_982_350))
    }

    @Test func aClosedSpanIsInclusive() {
        #expect(RangeRequest.parse("bytes=10-19") == .span(10, 19))
    }

    @Test func formsWeDoNotServeAreUnsatisfiable() {
        #expect(RangeRequest.parse("bytes=-500") == .unsatisfiable)        // suffix range
        #expect(RangeRequest.parse("bytes=0-1,5-6") == .unsatisfiable)     // multi-range
        #expect(RangeRequest.parse("bytes=9-3") == .unsatisfiable)         // end before start
        #expect(RangeRequest.parse("items=0-") == .unsatisfiable)
        #expect(RangeRequest.parse("bytes=x-") == .unsatisfiable)
    }

    @Test func resolveClampsToTheFile() {
        #expect(RangeRequest.whole.resolve(total: 100) == 0...99)
        #expect(RangeRequest.from(40).resolve(total: 100) == 40...99)
        #expect(RangeRequest.span(40, 500).resolve(total: 100) == 40...99)
        #expect(RangeRequest.from(100).resolve(total: 100) == nil)          // past the end → 416
        #expect(RangeRequest.unsatisfiable.resolve(total: 100) == nil)
        #expect(RangeRequest.whole.resolve(total: 0) == nil)
    }
}
