import Testing
@testable import DebridCore

@Suite struct ReleaseSubtitleTagsTests {
    let tags = ReleaseSubtitleTags()

    @Test(arguments: [
        "Oppenheimer.2023.1080p.BluRay.x264.HebSubs-GRP",
        "Oppenheimer.2023.1080p.BluRay.x264.HebSub",
        "Oppenheimer 2023 1080p Heb.Sub",
        "Oppenheimer.2023.1080p.Heb-Subs.WEB-DL",
        "Oppenheimer.2023.1080p.Hebrew.Subtitles.WEB-DL",
        "Oppenheimer.2023.1080p.Sub.Heb.WEB-DL",
        "Oppenheimer.2023.1080p.WEB-DL.HebSubbed",
        "אופנהיימר 2023 מתורגם 1080p",
        "Oppenheimer.2023.כתוביות.בעברית",
    ])
    func findsHebrewSubtitleTags(_ name: String) {
        #expect(tags.scan(name).languages == ["he"])
    }

    @Test(arguments: [
        "Oppenheimer.2023.1080p.HebDub",
        "Oppenheimer.2023.1080p.Heb.Dub",
        "Oppenheimer.2023.1080p.Hebrew.Dubbed",
        "Oppenheimer.2023.1080p.BluRay.x264-SPARKS",
        "Subway.Surfers.2023.1080p",
        "The.Hebrews.2023.1080p",
        "Movie.2023.1080p.Multi.Subs",
    ])
    func ignoresDubsAndLookalikes(_ name: String) {
        #expect(tags.scan(name).languages.isEmpty)
    }

    @Test func otherLanguagesAreReportedToo() {
        #expect(tags.scan("Amelie.2001.1080p.ENG.SUBS").languages == ["en"])
        #expect(tags.scan("Movie.2023.HebSub.EngSub").languages == ["he", "en"])
    }

    @Test func theRemainderHasTheTagBlankedOut() {
        let name = "Movie.2023.Heb.Sub.1080p"
        let scan = tags.scan(name)
        #expect(!scan.remainder.lowercased().contains("heb"))
        #expect(scan.remainder.contains("1080p"))
        #expect(scan.remainder.count == name.count)
    }
}
