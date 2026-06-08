import DebridCore
import DebridUI
import SwiftUI

/// tvOS Add-Profile screen — a real focusable form (name + emoji avatar), unlike an alert which
/// can't take text input on tvOS. Creating returns to the Who's-Watching picker.
struct AddProfileScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = ProfileAvatars.all.first ?? ProfileAvatars.fallback

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 24)]
    private let palette = ["gold", "blue", "green", "red", "purple"]
    private var color: String { palette[(session.activeProfiles?.roster.count ?? 0) % palette.count] }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: 44) {
                    Text("Add Profile").font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(Theme.Palette.textPrimary)

                    ZStack {
                        Circle().fill(Theme.Palette.color(for: color)).frame(width: 180, height: 180)
                        Text(avatar).font(.system(size: 100))
                    }

                    TextField("Name", text: $name).frame(maxWidth: 600).font(.title2)

                    Text("Pick an avatar").font(.title3).foregroundStyle(Theme.Palette.textSecondary)
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(ProfileAvatars.all, id: \.self) { e in
                            Button { avatar = e } label: {
                                Text(e).font(.system(size: 56))
                                    .frame(width: 110, height: 110)
                                    .background(avatar == e ? Theme.Palette.gold.opacity(0.30)
                                                            : Theme.Palette.surface1, in: Circle())
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 80)

                    HStack(spacing: 24) {
                        Button("Cancel") { dismiss() }
                        Button("Create") {
                            guard !trimmedName.isEmpty else { return }
                            Task {
                                await session.createProfile(name: trimmedName, colorTag: color, avatar: avatar)
                                dismiss()
                            }
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                    .font(.title3)
                }
                .padding(60)
            }
        }
    }
}
