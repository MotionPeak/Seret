import Testing
@testable import Seret

@Suite struct PagingTriggerTests {
    private let ids = (0..<20).map { "id-\($0)" }

    @Test func theTailTriggers() {
        #expect(PagingTrigger.shouldLoadMore(appeared: "id-19", in: ids))
        #expect(PagingTrigger.shouldLoadMore(appeared: "id-12", in: ids))   // last 8 = indices 12...19
    }

    @Test func theHeadDoesNot() {
        #expect(!PagingTrigger.shouldLoadMore(appeared: "id-0", in: ids))
        #expect(!PagingTrigger.shouldLoadMore(appeared: "id-11", in: ids))
    }

    @Test func anEmptyGridNeverTriggers() {
        #expect(!PagingTrigger.shouldLoadMore(appeared: "id-0", in: []))
    }

    @Test func aShortGridTriggersOnAnyItem() {
        let short = ["a", "b", "c"]
        #expect(PagingTrigger.shouldLoadMore(appeared: "a", in: short))
        #expect(PagingTrigger.shouldLoadMore(appeared: "b", in: short))
        #expect(PagingTrigger.shouldLoadMore(appeared: "c", in: short))
    }
}
