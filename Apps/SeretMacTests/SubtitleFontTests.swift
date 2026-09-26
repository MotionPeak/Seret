import CoreText
import DebridUI
import Testing

/// Every subtitle font the Mac offers must be a real face with HEBREW glyphs: libvlc draws letters a
/// face lacks in its fallback, so a Latin-only choice changed nothing at all for Hebrew subtitles.
struct SubtitleFontTests {
    @Test(arguments: SubtitlePreferences.Font.allCases)
    func everyChoiceIsARealFaceThatDrawsHebrew(_ font: SubtitlePreferences.Font) {
        guard let name = font.freetypeName else { return }      // Default: libvlc's own
        let face = CTFontCreateWithName(name as CFString, 20, nil)
        // CoreText quietly substitutes another face for a name it cannot find.
        let resolved = [CTFontCopyFamilyName(face) as String, CTFontCopyPostScriptName(face) as String]
        #expect(resolved.contains(name), "\(name) resolved to \(resolved)")
        var characters: [UniChar] = [0x05D0, 0x05E9, 0x05DF]   // alef, shin, final nun
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(face, &characters, &glyphs, characters.count),
                "\(name) has no Hebrew")
    }
}
