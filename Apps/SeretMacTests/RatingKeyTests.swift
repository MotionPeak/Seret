import SwiftUI
import Testing
@testable import Seret

@Suite struct RatingKeyTests {
    @Test func digitsMapToTheirValue() {
        for n in 1...9 {
            #expect(RatingKey.value(for: "\(n)", modifiers: []) == n)
        }
    }

    @Test func zeroIsTen() {
        #expect(RatingKey.value(for: "0", modifiers: []) == 10)
    }

    @Test func lettersAreIgnored() {
        #expect(RatingKey.value(for: "a", modifiers: []) == nil)
        #expect(RatingKey.value(for: "", modifiers: []) == nil)
        #expect(RatingKey.value(for: "12", modifiers: []) == nil)
    }

    @Test func commandDigitsPassThrough() {
        #expect(RatingKey.value(for: "1", modifiers: .command) == nil)
        #expect(RatingKey.value(for: "5", modifiers: .option) == nil)
        #expect(RatingKey.value(for: "7", modifiers: .control) == nil)
    }

    @Test func pressingTheCurrentRatingClearsIt() {
        #expect(RatingKey.next(current: 8, pressed: 8) == nil)
        #expect(RatingKey.next(current: 8, pressed: 6) == 6)
        #expect(RatingKey.next(current: nil, pressed: 6) == 6)
    }
}
