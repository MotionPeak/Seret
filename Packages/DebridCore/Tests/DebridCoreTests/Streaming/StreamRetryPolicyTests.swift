import Testing
@testable import DebridCore

struct StreamRetryPolicyTests {
    @Test func thePauseDoublesFromHalfASecondAndStopsGrowingAtFive() {
        let policy = StreamRetryPolicy.standard
        let pauses = (0...7).map { policy.delay(afterFailures: $0) }
        #expect(pauses == [.zero, .milliseconds(500), .seconds(1), .seconds(2), .seconds(4),
                           .seconds(5), .seconds(5), .seconds(5)])
    }
}
