/// One section's back/forward history. `path` is what the `NavigationStack` shows; `forwardStack`
/// holds routes displaced by `back()` or by a system pop, top (last element) = the one `forward()`
/// restores next.
struct NavigationHistory: Equatable {
    private(set) var path: [AppRoute] = []
    private(set) var forwardStack: [AppRoute] = []

    var canGoBack: Bool { !path.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// A new navigation: appends, and forgets whatever forward history existed — pushing from the
    /// middle of a back/forward chain abandons the branch ahead, same as a browser.
    mutating func push(_ route: AppRoute) {
        path.append(route)
        forwardStack.removeAll()
    }

    mutating func back() {
        guard let popped = path.popLast() else { return }
        forwardStack.append(popped)
    }

    mutating func forward() {
        guard let restored = forwardStack.popLast() else { return }
        path.append(restored)
    }

    mutating func popToRoot() {
        path.removeAll()
        forwardStack.removeAll()
    }

    /// The `NavigationStack` binding's setter. A strict prefix of `path` is a pop the system did
    /// (dragged back, or the ‹ button before Task 2 hides it) — record the popped routes, closest
    /// to the new tail first, so `forward()` brings them back one at a time in the order they left.
    /// Anything else is a new navigation: replace the path and drop the forward branch.
    mutating func setPath(_ new: [AppRoute]) {
        if new.count < path.count, Array(path.prefix(new.count)) == new {
            let popped = path[new.count...]
            forwardStack.append(contentsOf: popped.reversed())
        } else {
            forwardStack.removeAll()
        }
        path = new
    }
}
