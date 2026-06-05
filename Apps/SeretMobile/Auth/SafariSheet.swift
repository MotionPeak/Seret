import SafariServices
import SwiftUI

/// Opens a URL (the Real‑Debrid device-authorization page) in an in-app Safari sheet.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `URL` isn't `Identifiable`; wrap it so it can drive `.sheet(item:)`.
struct PresentedURL: Identifiable {
    let id = UUID()
    let url: URL
}
