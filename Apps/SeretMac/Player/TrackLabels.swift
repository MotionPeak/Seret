import DebridCore
import DebridUI

/// How a track is named in the Audio & Subtitles panel — the same rules as the iPhone and TV:
/// a downloaded subtitle by the language row that fetched it (libvlc calls it "Track 3"), then a
/// bracketed language in the track's name, then its language code spelled out, then the raw name;
/// and a language that appears twice is numbered ("German 1", "German 2").
@MainActor
enum TrackLabels {
    static func language(of track: MediaTrack, downloadedLanguage: String?) -> String {
        if let downloadedLanguage { return downloadedLanguage }
        if let r = track.name.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            let inner = track.name[r].dropFirst().dropLast()
            if !inner.isEmpty { return String(inner) }
        }
        if let code = track.language, !code.isEmpty { return PlayerModel.languageName(code) }
        return track.name
    }

    static func labeled(_ tracks: [MediaTrack],
                        languageOf: (MediaTrack) -> String) -> [(track: MediaTrack, label: String)] {
        let names = tracks.map(languageOf)
        let totals = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return zip(tracks, names).map { track, name in
            seen[name, default: 0] += 1
            let label = (totals[name] ?? 1) > 1 ? "\(name) \(seen[name]!)" : name
            return (track, label)
        }
    }
}
