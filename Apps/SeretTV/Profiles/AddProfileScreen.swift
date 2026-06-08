import DebridCore
import DebridUI
import SwiftUI

/// tvOS Add-Profile screen — a real focusable form (name + emoji avatar), unlike an alert which
/// can't take text input on tvOS. Create is reachable without scrolling, and a name is optional
/// (a default is used) so you can make a profile just by picking an emoji.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ProfileAvatars.all.first ?? ProfileAvatars.fallback

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 22)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var count: Int { session.activeProfiles?.roster.count ?? 0 }
    private var color: String { palette[count % palette.count] }
    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Profile \(count + 1)" : t
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 36) {
                    // Header: preview + name + actions — all above the avatar grid so Create is
                    // always reachable.
                    VStack(spacing: 24) {
                        Text("Add Profile").font(.system(size: 46, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        ZStack {
                            Circle().fill(Theme.Palette.color(for: color)).frame(width: 170, height: 170)
                                .goldGlow(20, opacity: 0.25)
                            Text(avatar).font(.system(size: 96))
                        }
                        TextField("Name (optional)", text: $name)
                            .frame(maxWidth: 560).font(.title3)
                            .padding(.vertical, 10).padding(.horizontal, 24)
                            .background(Theme.Palette.surface1, in: RoundedRectangle(cornerRadius: 14))
                        HStack(spacing: 24) {
                            Button("Cancel") { dismiss() }
                            Button("Create") {
                                let n = finalName, c = color, a = avatar
                                Task { await session.createProfile(name: n, colorTag: c, avatar: a); dismiss() }
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.Palette.gold)
                        }
                        .font(.title3)
                    }

                    Text("Pick an avatar").font(.title3).foregroundStyle(Theme.Palette.textSecondary)
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(ProfileAvatars.all, id: \.self) { e in
                            Button { avatar = e } label: {
                                Text(e).font(.system(size: 54))
                                    .frame(width: 104, height: 104)
                                    .background(avatar == e ? Theme.Palette.color(for: color).opacity(0.35)
                                                            : Theme.Palette.surface1, in: Circle())
                                    .overlay(Circle().strokeBorder(
                                        avatar == e ? Theme.Palette.gold : .clear, lineWidth: 4))
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .padding(60)
            }
        }
    }
}
