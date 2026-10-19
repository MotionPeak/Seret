import DebridUI
import SwiftUI

/// A profile's emoji avatar in its colour circle, drawn from the TV palette.
///
/// The shared `DebridUI.ProfileAvatarImage` fills an untagged profile with the mobile brand colour,
/// which the TV no longer draws; this is the same avatar with `Theme.Palette.avatarFill(for:)`
/// behind it, so the default profile is indigo here and unchanged on the other devices.
struct AvatarCircle: View {
    let token: String
    let diameter: CGFloat
    let colorTag: String

    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.avatarFill(for: colorTag))
            Text(ProfileAvatars.emoji(token))
                .font(.system(size: diameter * 0.56))
                .minimumScaleFactor(0.5)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }
}
