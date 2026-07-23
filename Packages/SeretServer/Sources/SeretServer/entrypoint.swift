import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        let config = try ServerConfig.fromEnvironment()
        let app = try await Application.make(.detect())
        do {
            try await configure(app, config: config)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
