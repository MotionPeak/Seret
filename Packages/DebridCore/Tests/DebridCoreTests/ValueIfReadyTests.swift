import Testing
@testable import DebridCore

@Suite struct ValueIfReadyTests {
    @Test func aValueReadyInTimeIsReturned() async {
        let task = Task { 42 }
        #expect(await valueIfReady(of: task, within: .seconds(5)) == 42)
    }

    /// Late is nil — and the task is not cancelled, so whoever else awaits it still gets the value.
    @Test func aLateValueIsNilButStillArrives() async {
        let task = Task { () -> Int in
            try? await Task.sleep(for: .milliseconds(300))
            return Task.isCancelled ? -1 : 7
        }
        #expect(await valueIfReady(of: task, within: .milliseconds(20)) == nil)
        #expect(await task.value == 7)
    }
}
