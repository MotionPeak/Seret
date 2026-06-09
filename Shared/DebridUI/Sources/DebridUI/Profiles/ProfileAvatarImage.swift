import SwiftUI

/// Renders a profile's avatar: a local emoji centred in the profile's colour circle. Fully
/// on-device (no network), so it always shows instantly. Shared by both apps so every avatar —
/// picker, launch gate, shell button — looks identical.
public struct ProfileAvatarImage: View {
    private let token: String
    private let diameter: CGFloat
    private let colorTag: String

    public init(token: String, diameter: CGFloat, colorTag: String) {
        self.token = token
        self.diameter = diameter
        self.colorTag = colorTag
    }

    public var body: some View {
        let hex = ProfileAvatars.backgroundHex(forColorTag: colorTag)
        ZStack {
            Circle().fill(Color(avatarHex: hex))
            Text(ProfileAvatars.emoji(token))
                .font(.system(size: diameter * 0.56))
                .minimumScaleFactor(0.5)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}

private extension Color {
    /// Build a Color from a hex string without '#' (e.g. "EBC11D").
    init(avatarHex hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}
