import AuthenticationServices
import Foundation
import os

private let logger = Logger(subsystem: "com.fridgecheck.app", category: "Auth")

enum AuthError: LocalizedError {
    case missingIdentityToken
    case serverError(String)
    case networkError(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: return "Apple did not return an identity token."
        case .serverError(let msg): return "Server error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .cancelled: return "Sign in was cancelled."
        }
    }
}

private struct AppleExchangeRequest: Encodable {
    let identityToken: String
}

private struct AppleExchangeResponse: Decodable {
    let session: String
    let userId: String
}

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    private let tokenKey = "session_token"
    private let emailKey = "session_email"

    private(set) var sessionToken: String?
    private(set) var userEmail: String?
    var isSigningIn = false
    var errorMessage: String?

    var isSignedIn: Bool { sessionToken != nil }

    private init() {
        self.sessionToken = KeychainStore.get(tokenKey)
        self.userEmail = KeychainStore.get(emailKey)
    }

    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            errorMessage = AuthError.missingIdentityToken.errorDescription
            return
        }

        isSigningIn = true
        errorMessage = nil

        do {
            let resp = try await exchange(identityToken: token)
            KeychainStore.set(resp.session, for: tokenKey)
            if let email = credential.email {
                KeychainStore.set(email, for: emailKey)
                self.userEmail = email
            }
            self.sessionToken = resp.session
            isSigningIn = false
        } catch {
            logger.error("Apple exchange failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isSigningIn = false
        }
    }

    func signOut() {
        KeychainStore.delete(tokenKey)
        KeychainStore.delete(emailKey)
        sessionToken = nil
        userEmail = nil
    }

    private func exchange(identityToken: String) async throws -> AppleExchangeResponse {
        var request = URLRequest(url: AppConfig.serverURL.appendingPathComponent("/v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AppleExchangeRequest(identityToken: identityToken)
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.serverError("No response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AuthError.serverError(body)
        }
        do {
            return try JSONDecoder().decode(AppleExchangeResponse.self, from: data)
        } catch {
            throw AuthError.serverError("Malformed response")
        }
    }
}

