import Testing
@testable import Seret

@Suite struct PersonSectionsTests {
    @Test func actorsListActingFirst() {
        let sections = PersonSections.make(actingCount: 3, directingCount: 2, knownFor: "Acting")
        #expect(sections == [.acting, .directing])
    }

    @Test func directorsListDirectingFirst() {
        let sections = PersonSections.make(actingCount: 3, directingCount: 2, knownFor: "Directing")
        #expect(sections == [.directing, .acting])
    }

    @Test func emptySectionsAreDropped() {
        #expect(PersonSections.make(actingCount: 0, directingCount: 2, knownFor: "Directing") == [.directing])
        #expect(PersonSections.make(actingCount: 3, directingCount: 0, knownFor: "Acting") == [.acting])
    }

    @Test func nothingIsNothing() {
        #expect(PersonSections.make(actingCount: 0, directingCount: 0, knownFor: nil) == [])
    }
}
