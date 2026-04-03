import Foundation

struct RealtimeTokenResponse: Decodable {
    let apiKey: String
}

enum TokenServiceError: LocalizedError {
    case invalidResponse
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The token server returned an invalid response."
        case .missingToken:
            return "The token server response was missing the client token."
        }
    }
}

struct TokenService {
    var session: URLSession = .shared

    func backendSummary() -> String {
        AppConfiguration.backendBaseURL.absoluteString
    }

    func fetchRealtimeToken() async throws -> String {
        let endpoint = AppConfiguration.backendBaseURL.appendingPathComponent("api/realtime-token")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
                throw NSError(domain: "TokenService", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: message.error
                ])
            }

            throw TokenServiceError.invalidResponse
        }

        let token = try JSONDecoder().decode(RealtimeTokenResponse.self, from: data)
        guard !token.apiKey.isEmpty else {
            throw TokenServiceError.missingToken
        }

        return token.apiKey
    }

    func checkBackendHealth() async throws {
        let endpoint = AppConfiguration.backendBaseURL.appendingPathComponent("api/health")
        let (_, response) = try await session.data(from: endpoint)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw TokenServiceError.invalidResponse
        }
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
}
