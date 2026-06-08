import Foundation

/// Profile avatars are generated art from the free, no-auth DiceBear HTTP API (PNG output, so
/// `AsyncImage` renders them natively). An avatar is stored as a compact `"style:seed"` token; the
/// image URL is built on demand. A curated MIXED set (robots, pixel-art, faces, monsters …) gives
/// lots of variety in the picker.
public enum ProfileAvatars {
    /// `"style:seed"` tokens, mixing many DiceBear styles for variety.
    public static let all: [String] = [
        "bottts:Apollo", "pixel-art:Hero", "adventurer:Mia", "fun-emoji:Ziggy",
        "lorelei:Luna", "thumbs:Chip", "micah:Felix", "notionists:Ari",
        "bottts:Vega", "pixel-art:Zed", "adventurer:Kai", "fun-emoji:Pop",
        "open-peeps:Rio", "big-smile:Joy", "croodles:Bean", "micah:Jude",
        "bottts:Pixel", "pixel-art:Boss", "adventurer:Sky", "fun-emoji:Bolt",
        "lorelei:Ivy", "thumbs:Doodle", "notionists:Nova", "open-peeps:Sage",
        "bottts-neutral:Zap", "big-ears:Milo", "adventurer-neutral:Ash", "big-smile:Sunny",
        "croodles:Pip", "miniavs:Toad", "lorelei:Nyx", "fun-emoji:Mango",
    ]

    /// Fallback for profiles with no (or a legacy emoji) avatar.
    public static let fallback = "fun-emoji:Seret"

    /// The DiceBear PNG URL for a `"style:seed"` token. `backgroundColor` is a hex WITHOUT '#'
    /// (DiceBear fills the square so it reads as a solid circle). nil for an invalid token.
    public static func imageURL(for token: String, size: Int = 256, backgroundColor: String? = nil) -> URL? {
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var c = URLComponents(string: "https://api.dicebear.com/10.x/\(parts[0])/png")
        var items = [URLQueryItem(name: "seed", value: String(parts[1])),
                     URLQueryItem(name: "size", value: String(size)),
                     URLQueryItem(name: "radius", value: "50")]
        if let backgroundColor { items.append(URLQueryItem(name: "backgroundColor", value: backgroundColor)) }
        c?.queryItems = items
        return c?.url
    }

    /// Resolve a stored avatar value to a usable token (legacy emoji / empty → fallback).
    public static func token(_ stored: String) -> String {
        stored.contains(":") ? stored : fallback
    }

    /// DiceBear-friendly hex (no '#') for a profile color tag — the avatar background.
    public static func backgroundHex(forColorTag tag: String) -> String {
        switch tag {
        case "blue":   return "3B82F6"
        case "green":  return "22C55E"
        case "red":    return "EF4444"
        case "purple": return "A855F7"
        default:        return "EBC11D"   // gold
        }
    }
}
