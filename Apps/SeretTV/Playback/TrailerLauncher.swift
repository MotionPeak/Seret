import AVKit
import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// A "Trailer" button for tvOS: resolves the title's trailer to a playable stream on appear and
/// plays it full-screen in-app (AVPlayer). It shows IMMEDIATELY (a disabled loading pill, so the
/// action row doesn't shift when the trailer resolves) in the same gold-glass style as the other
/// action buttons; once the in-app stream is ready it becomes a normal, pressable Trailer button.
/// If extraction fails it removes itself — we never deep-link to the YouTube app (dead end on tvOS).
struct TrailerButton: View {
    let tmdbID: Int?
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var preparing = true
    @State private var showing = false

    var body: some View {
        Group {
            if let model, model.streamURL != nil {
                Button { showing = true } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(SeretActionButtonStyle())
                .fullScreenCover(isPresented: $showing) { cover(model) }
            } else if preparing {
                // Reserve the row's space + match the others — just disabled with a spinner.
                Button {} label: {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Trailer")
                    }
                }
                .buttonStyle(SeretActionButtonStyle())
                .disabled(true)
                .opacity(0.55)
            } else {
                // Extraction failed → no trailer. A zero-size host keeps `.task` alive.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil else { return }
            preparing = true
            let m = session.makeTrailerModel()
            model = m
            await m?.prepare(tmdbID: tmdbID, kind: kind)
            preparing = false
        }
    }

    @ViewBuilder private func cover(_ m: TrailerModel) -> some View {
        if let url = m.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // canOffer gates on a ready stream, so this shouldn't happen — but never deep-link to
            // YouTube (dead end on tvOS); just dismiss.
            Color.black.ignoresSafeArea().onAppear { showing = false }
        }
    }
}
