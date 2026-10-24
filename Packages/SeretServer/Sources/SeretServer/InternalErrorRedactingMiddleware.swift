import Vapor

/// Turns any error that is not an `Abort` into a generic 500 before Vapor's `ErrorMiddleware` sees
/// it.
///
/// Outside the production environment, `ErrorMiddleware` answers a non-`Abort` error with
/// `String(describing: error)` and logs the same text. An internal error can carry a URL that holds
/// a secret (TorBox puts the account key in `requestdl`'s query), so neither the browser nor the
/// docker log may see its description. Routes that mean to tell the browser something throw an
/// `Abort` with a reason, and those pass through untouched.
struct InternalErrorRedactingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as any AbortError {
            throw error
        } catch {
            // The type name says which subsystem failed without echoing anything it carries.
            request.logger.error("\(request.method) \(request.url.path) failed: \(String(reflecting: type(of: error)))")
            throw Abort(.internalServerError, reason: "Something went wrong.")
        }
    }
}
