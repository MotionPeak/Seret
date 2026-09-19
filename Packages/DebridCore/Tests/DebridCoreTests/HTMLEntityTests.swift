import Testing
@testable import DebridCore

/// Letterboxd renders a film's display name into an HTML *attribute*, so every title that contains
/// an apostrophe or an ampersand arrives escaped. Decoding is therefore not a nicety: an undecoded
/// name is both shown to the owner verbatim and searched on TMDB verbatim, and TMDB answers a
/// query containing `&#039;` with nothing at all.
struct HTMLEntityTests {
    @Test func decodesTheApostropheLetterboxdActuallyEmits() {
        #expect(HTMLEntities.decode("Honey Don&#039;t! (2025)") == "Honey Don't! (2025)")
        #expect(HTMLEntities.decode("Butcher&#039;s Stain (2025)") == "Butcher's Stain (2025)")
    }

    @Test func decodesTheNamedFive() {
        #expect(HTMLEntities.decode("Dungeons &amp; Dragons") == "Dungeons & Dragons")
        #expect(HTMLEntities.decode("&lt;tag&gt;") == "<tag>")
        #expect(HTMLEntities.decode("&quot;Quoted&quot;") == "\"Quoted\"")
        #expect(HTMLEntities.decode("Ocean&apos;s Eleven") == "Ocean's Eleven")
    }

    @Test func decodesNumericAndHexReferences() {
        #expect(HTMLEntities.decode("Caf&#233;") == "Café")
        #expect(HTMLEntities.decode("Caf&#xE9;") == "Café")
        #expect(HTMLEntities.decode("&#x1F600;") == "😀")
    }

    /// `&amp;#039;` is a literal ampersand followed by text, not a nested escape. Decoding twice
    /// would turn it into an apostrophe and quietly corrupt a title.
    @Test func decodesOnlyOnePass() {
        #expect(HTMLEntities.decode("&amp;#039;") == "&#039;")
    }

    @Test func leavesOrdinaryTextAndLoneAmpersandsAlone() {
        #expect(HTMLEntities.decode("Speed (1994)") == "Speed (1994)")
        #expect(HTMLEntities.decode("Fish & Chips") == "Fish & Chips")
        // An unterminated or unknown reference is text, not an error.
        #expect(HTMLEntities.decode("A&B &notareal; &#") == "A&B &notareal; &#")
    }

    /// A malformed numeric reference must not crash or swallow the rest of the string.
    @Test func survivesMalformedNumericReferences() {
        #expect(HTMLEntities.decode("&#;x") == "&#;x")
        #expect(HTMLEntities.decode("&#99999999999;") == "&#99999999999;")
        #expect(HTMLEntities.decode("&#xZZ;") == "&#xZZ;")
    }
}
