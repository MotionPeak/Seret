import Foundation

/// Build-time secrets surfaced into Info.plist from Secrets.xcconfig.
public enum Secrets {
    /// TMDB v3 API key: `TMDB_API_KEY` (Secrets.xcconfig) → `TMDBAPIKey` (Info.plist) → here.
    public static var tmdbAPIKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? ""
        assert(!key.isEmpty,
               "TMDB_API_KEY missing — copy Secrets.example.xcconfig → Secrets.xcconfig and set it.")
        return key
    }

    /// OpenSubtitles API key: `OPENSUBTITLES_API_KEY` (Secrets.xcconfig) → `OpenSubtitlesAPIKey` (Info.plist) → here.
    /// Empty string when unset — callers treat empty as "subtitles unavailable."
    public static var openSubtitlesAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OpenSubtitlesAPIKey") as? String) ?? ""
    }

    /// OMDb API key: `OMDB_API_KEY` (Secrets.xcconfig) → `OMDBAPIKey` (Info.plist) → here.
    /// Empty string when unset — callers treat empty as "ratings unavailable."
    public static var omdbAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OMDBAPIKey") as? String) ?? ""
    }

    /// Trakt client id: `TRAKT_CLIENT_ID` (Secrets.xcconfig) → `TraktClientID` (Info.plist) → here.
    /// Empty string when unset — callers treat empty as "Trakt unavailable."
    public static var traktClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TraktClientID") as? String) ?? ""
    }

    /// Trakt client secret: `TRAKT_CLIENT_SECRET` (Secrets.xcconfig) → `TraktClientSecret` (Info.plist) → here.
    public static var traktClientSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "TraktClientSecret") as? String) ?? ""
    }

    /// Whether a Trakt app is configured at all.
    public static var traktConfigured: Bool { !traktClientID.isEmpty }
}
