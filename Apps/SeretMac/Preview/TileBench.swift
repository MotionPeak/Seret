#if DEBUG
import AppKit
import DebridCore
import SwiftUI

/// `-tileBench` — the cost scrolling a grid pays whenever a row comes into view: build, lay out and
/// render 120 real `PosterTile`s off screen (no display or window needed), fifteen times, and report
/// the median. Written to `Caches/scrollbench.txt` (see `ScrollBench.report`), then quits.
@MainActor
enum TileBench {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-tileBench") }

    private struct Slot: Identifiable {
        let id: Int
        let item: MediaItem
    }

    static func run() {
        let films = Fixture.films
        let slots = (0..<120).map { Slot(id: $0, item: films[$0 % films.count]) }
        let grid = PosterGrid(items: slots) { slot in
            PosterTile(model: PosterTileModel.library(slot.item),
                       state: PosterTileState(badge: .none, decor: PosterDecor(dimsWatched: true)),
                       actions: .make(kind: slot.item.kind, owned: true, watched: false, onWatchlist: false),
                       perform: { _, _ in })
        }
        var build: [Double] = []
        var draw: [Double] = []
        for _ in 0..<15 {
            let start = CACurrentMediaTime()
            let host = NSHostingView(rootView: grid.frame(width: 1400).environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 1400, height: 6200)
            host.layoutSubtreeIfNeeded()
            let built = CACurrentMediaTime()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
            }
            build.append(built - start)
            draw.append(CACurrentMediaTime() - built)
        }
        let b = build.sorted()[build.count / 2] * 1000
        let d = draw.sorted()[draw.count / 2] * 1000
        ScrollBench.report(String(format: "[tileBench] 120 tiles: build+layout %.1f ms (%.2f ms/tile) · draw %.1f ms (%.2f ms/tile)",
                                  b, b / 120, d, d / 120))
        NSApp.terminate(nil)
    }
}
#endif
