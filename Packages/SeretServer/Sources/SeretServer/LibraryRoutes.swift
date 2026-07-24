import Vapor
import DebridCore

func registerLibraryRoutes(_ app: Application) {
    // The organized movie library. Builds on first request if the boot warm-up hasn't finished.
    app.get("api", "library") { req async throws -> [LibraryItemDTO] in
        let lib = req.application.library
        if await lib.isEmpty { _ = try await lib.refresh() }
        let items = await lib.items
        return items.filter { $0.kind == .movie }.map(LibraryItemDTO.init)
    }

    app.get("api", "item", ":id") { req async throws -> LibraryItemDTO in
        let id = try req.parameters.require("id")
        guard let item = await req.application.library.item(id: id) else { throw Abort(.notFound) }
        return LibraryItemDTO(item)
    }

    app.post("api", "refresh") { req async throws -> [LibraryItemDTO] in
        let items = try await req.application.library.refresh()
        return items.filter { $0.kind == .movie }.map(LibraryItemDTO.init)
    }
}
