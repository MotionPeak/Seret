import Foundation
import TVServices

/// Fills the Apple TV Top Shelf (the banner above the top row of apps) with Seret's brand art:
/// one full-screen carousel item whose background is the "Range" landscape loop.
///
/// The still poster shows first; the looping video replaces it while Seret's icon is focused.
/// Both ship inside this extension (rendered by `Scripts/topshelf/render.sh`), so the Top Shelf
/// never needs the network. Selecting the item opens the app.
final class ContentProvider: TVTopShelfContentProvider {
    // The completion-handler form: TVServices' content types aren't Sendable, so the async
    // override can't hand them back across its isolation boundary under Swift 6.
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        let item = TVTopShelfCarouselItem(identifier: "seret.range")
        let bundle = Bundle(for: ContentProvider.self)
        item.setImageURL(bundle.url(forResource: "range-poster-1x", withExtension: "jpg"), for: .screenScale1x)
        item.setImageURL(bundle.url(forResource: "range-poster-2x", withExtension: "jpg"), for: .screenScale2x)
        item.cinemagraphURL = bundle.url(forResource: "range", withExtension: "mp4")
        if let open = URL(string: "seret://") {
            item.displayAction = TVTopShelfAction(url: open)
        }
        completionHandler(TVTopShelfCarouselContent(style: .details, items: [item]))
    }
}
