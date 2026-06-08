import DebridCore
import DebridUI
import SwiftUI

/// iOS Add-Profile sheet — name + emoji avatar picker. Creating returns to the picker.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ProfileAvatars.all.first ?? ProfileAvatars.fallback

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 14)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var count: Int { session.activeProfiles?.roster.count ?? 0 }
    private var color: String { palette[count % palette.count] }
    private var finalName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Profile \(count + 1)" : t
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(spacing: 28) {
                        ProfileAvatarImage(token: avatar, diameter: 120, colorTag: color)
                            .padding(.top, 12)

                        TextField("Name (optional)", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 24)

                        Text("Pick an avatar").font(Theme.Typo.headline())
                            .foregroundStyle(Theme.Palette.textSecondary)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(ProfileAvatars.all, id: \.self) { e in
                                Button { avatar = e } label: {
                                    ProfileAvatarImage(token: e, diameter: 60, colorTag: color)
                                        .overlay(Circle().strokeBorder(
                                            avatar == e ? Theme.Palette.gold : .clear, lineWidth: 3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Add Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let n = finalName, c = color, a = avatar
                        Task {
                            await session.createProfile(name: n, colorTag: c, avatar: a)
                            dismiss()
                        }
                    }
                    .tint(Theme.Palette.gold)
                }
            }
        }
    }
}
