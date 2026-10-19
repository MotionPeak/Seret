import Testing
import Foundation
@testable import DebridUI
import DebridCore

/// A sleeper whose Nth call suspends until the test releases gate N.
private final class GatedSleeper: @unchecked Sendable {
    let gates: [AsyncGate]
    let entered = AsyncCounter()
    private let lock = NSLock()
    private var next = 0
    init(count: Int) { gates = (0..<count).map { _ in AsyncGate() } }
    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] _ in
            let i = lock.withLock { () -> Int in defer { next += 1 }; return next }
            await entered.increment()
            await gates[i].wait()
        }
    }
}

@Suite struct FocusPreviewModelTests {
    private static func subject(_ id: String) -> PreviewSubject {
        PreviewSubject(item: MediaItem(id: id, kind: .movie, title: id, year: nil, sources: [], seasons: []))
    }

    @MainActor @Test func onlyTheLastFocusSettles() async {
        let sleeper = GatedSleeper(count: 3)
        let model = FocusPreviewModel(sleeper: sleeper.sleep)
        let (a, b, c) = (Self.subject("a"), Self.subject("b"), Self.subject("c"))
        // One at a time, so sleeper call N is exactly focus N (task start order isn't a contract).
        model.focus(a); await sleeper.entered.wait(atLeast: 1)
        model.focus(b); await sleeper.entered.wait(atLeast: 2)
        model.focus(c); await sleeper.entered.wait(atLeast: 3)
        #expect(model.shown == nil)

        await sleeper.gates[0].open(); await settle()
        #expect(model.shown == nil)                  // a was superseded
        await sleeper.gates[1].open(); await settle()
        #expect(model.shown == nil)                  // b was superseded
        await sleeper.gates[2].open()
        await until { model.shown == c }
        #expect(model.shown == c)
    }

    @MainActor @Test func showImmediatelyIsInstantAndCancelsAPendingFocus() async {
        let sleeper = GatedSleeper(count: 1)
        let model = FocusPreviewModel(sleeper: sleeper.sleep)
        model.focus(Self.subject("pending"))
        await sleeper.entered.wait(atLeast: 1)
        let x = Self.subject("x")
        model.showImmediately(x)
        #expect(model.shown == x)
        await sleeper.gates[0].open(); await settle()
        #expect(model.shown == x)                    // the pending focus never lands
    }

    @MainActor @Test func refocusingTheShownSubjectCancelsAPendingOne() async {
        let sleeper = GatedSleeper(count: 1)
        let model = FocusPreviewModel(sleeper: sleeper.sleep)
        let (a, b) = (Self.subject("a"), Self.subject("b"))
        model.showImmediately(a)
        model.focus(b)                               // glided onto b…
        await sleeper.entered.wait(atLeast: 1)
        model.focus(a)                               // …and straight back
        await sleeper.gates[0].open(); await settle()
        #expect(model.shown == a)
    }

    @MainActor @Test func aThrowingSleeperLeavesShownAlone() async {
        struct Cancelled: Error {}
        let model = FocusPreviewModel(sleeper: { _ in throw Cancelled() })
        model.focus(Self.subject("a"))
        await settle()
        #expect(model.shown == nil)
    }

    @MainActor @Test func theDebounceDurationIsPassedToTheSleeper() async {
        let seen = AsyncCounter()
        final class Box: @unchecked Sendable { var d: Duration? }
        let box = Box()
        let model = FocusPreviewModel(debounce: .milliseconds(150), sleeper: { d in
            box.d = d; await seen.increment()
        })
        model.focus(Self.subject("a"))
        await seen.wait(atLeast: 1)
        await until { model.shown?.id == "a" }
        #expect(box.d == .milliseconds(150))
        #expect(model.shown?.id == "a")
    }
}
