import Foundation
import Observation

/// User-customizable subtitle appearance, shared across every movie and episode. Pure value type;
/// the VLCKit translation (font name → `--freetype-font`, color → `--freetype-color`, size →
/// `currentSubTitleFontScale`) lives in the player engine so this stays UI/VLCKit-free.
public struct SubtitlePreferences: Codable, Sendable, Equatable {
    public enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large, extraLarge
        /// Multiplier for VLCKit's `currentSubTitleFontScale` (1.0 = VLCKit default).
        public var scale: Double {
            switch self {
            case .small: 0.7
            case .medium: 1.0
            case .large: 1.4
            case .extraLarge: 1.8
            }
        }
        public var label: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }
    }

    public enum Font: String, Codable, CaseIterable, Sendable {
        case system, sans, serif, rounded, monospace, rubik
        /// VLCKit `--freetype-font` value; nil = leave VLCKit's bundled default.
        public var freetypeName: String? {
            #if os(macOS)
            // Every choice must carry HEBREW glyphs. libvlc draws letters a face lacks in its
            // fallback, Lucida Grande, so a Latin-only face changed nothing for Hebrew subtitles:
            // the owner picked Sans and saw no difference at all. (Helvetica Neue IS libvlc's Mac
            // default, so Sans didn't even change Latin; Georgia, Arial Rounded and Menlo have no
            // Hebrew.) The Rubik faces go by PostScript name: by family, libvlc picks the bundled
            // Rubik-Regular, which is Latin-only. Each checked by rendering through libvlc.
            switch self {
            case .system: nil
            case .sans: "Arial"
            case .serif: "Times New Roman"
            case .rounded: "Rubik-SemiBold"
            case .monospace: "Courier New"
            case .rubik: "Rubik-Medium"
            }
            #else
            switch self {
            case .system: nil
            case .sans: "Helvetica Neue"
            case .serif: "Georgia"
            case .rounded: "Arial Rounded MT Bold"
            case .monospace: "Menlo"
            case .rubik: "Rubik"               // bundled (Rubik-Regular.ttf, registered via UIAppFonts)
            }
            #endif
        }
        public var label: String {
            switch self {
            case .system: "Default"
            case .sans: "Sans"
            case .serif: "Serif"
            case .rounded: "Rounded"
            case .monospace: "Monospace"
            case .rubik: "Rubik"
            }
        }
    }

    public enum Color: String, Codable, CaseIterable, Sendable {
        case white, yellow, cyan, green, pink
        /// VLCKit `--freetype-color` value (0xRRGGBB integer).
        public var rgb: Int {
            switch self {
            case .white: 0xFFFFFF
            case .yellow: 0xFFFF00
            case .cyan: 0x00FFFF
            case .green: 0x00FF00
            case .pink: 0xFF69B4
            }
        }
        public var label: String {
            switch self {
            case .white: "White"
            case .yellow: "Yellow"
            case .cyan: "Cyan"
            case .green: "Green"
            case .pink: "Pink"
            }
        }
    }

    public var size: Size
    public var font: Font
    public var color: Color

    public init(size: Size = .medium, font: Font = .system, color: Color = .white) {
        self.size = size
        self.font = font
        self.color = color
    }

    public static let `default` = SubtitlePreferences()
}

/// Observable, `UserDefaults`-persisted home for `SubtitlePreferences`. Lives on `AppSession` so the
/// Settings UI binds to it and the player engine reads it at construction.
@MainActor
@Observable
public final class SubtitleSettingsModel {
    public var preferences: SubtitlePreferences { didSet { persist() } }

    private let defaults: UserDefaults
    private static let key = "seret.subtitlePreferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SubtitlePreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.key) }
    }
}
