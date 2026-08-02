import Foundation

enum ParseError: LocalizedError {
    case noTextFound
    case decodingFailed
    case backendUnavailable

    var errorDescription: String? {
        switch self {
        case .noTextFound: "No text found in the photo. Try again with more of the menu in frame."
        case .decodingFailed: "Couldn't read the menu from the server response."
        case .backendUnavailable: "Couldn't reach the server. Check your connection."
        }
    }
}

/// The seam where the backend plugs in.
///
/// `FixtureParseService` is the Phase 0 stand-in; a `BackendParseService`
/// calling the Cloudflare Worker replaces it once the model benchmark has
/// picked a model and validated cost. Everything above this protocol —
/// capture, result list, detail, ordering mode — is unaffected by that swap.
protocol ParseService {
    func parse(imageData: Data) async throws -> MenuParse
}

/// Returns a bundled fixture parse (derived from the benchmark ground-truth
/// labels) after a realistic delay, so loading states are exercised.
struct FixtureParseService: ParseService {
    var delay: Duration = .milliseconds(1200)

    func parse(imageData: Data) async throws -> MenuParse {
        try await Task.sleep(for: delay)
        guard let url = Bundle.main.url(forResource: "fixture_menu", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parse = try? JSONDecoder().decode(MenuParse.self, from: data)
        else {
            throw ParseError.decodingFailed
        }
        return parse
    }
}
