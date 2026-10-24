import Foundation

/// A signed-in user and their access token.
struct AuthSession: Codable, Equatable {
    var userID: String
    var email: String
    var accessToken: String
    var refreshToken: String
}

enum AuthError: LocalizedError {
    case notConfigured
    case badResponse(Int, String)
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Sign-in isn't set up yet."
        case .badResponse(_, let msg): return msg
        case .transport(let d): return "Network problem: \(d)"
        case .decoding: return "Unexpected response from the server."
        }
    }
}

/// Email 6-digit OTP auth against Supabase's GoTrue REST API — same backend the
/// web app uses, no SDK dependency. Sends a code to the user's email, then
/// verifies it to get a session. Session is persisted so the user stays signed
/// in across launches.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AuthSession?

    private let sessionKey = "nutriwear.auth.session.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let s = try? JSONDecoder().decode(AuthSession.self, from: data) {
            session = s
        }
    }

    var isSignedIn: Bool { session != nil }
    var isConfigured: Bool { SupabaseConfig.isConfigured }

    // MARK: - OTP flow

    /// Send a 6-digit code to the given email. Creates the user if new.
    func sendCode(to email: String) async throws {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey else {
            throw AuthError.notConfigured
        }
        let url = URL(string: "\(base)/auth/v1/otp")!
        let body: [String: Any] = ["email": email, "create_user": true]
        _ = try await post(url, apiKey: key, body: body, auth: nil)
    }

    /// Verify the emailed code and establish a session.
    func verifyCode(email: String, token: String) async throws {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey else {
            throw AuthError.notConfigured
        }
        let url = URL(string: "\(base)/auth/v1/verify")!
        let body: [String: Any] = ["type": "email", "email": email, "token": token]
        let data = try await post(url, apiKey: key, body: body, auth: nil)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String,
            let refreshToken = json["refresh_token"] as? String,
            let user = json["user"] as? [String: Any],
            let userID = user["id"] as? String
        else {
            throw AuthError.decoding
        }
        let emailFromServer = (user["email"] as? String) ?? email
        let s = AuthSession(userID: userID, email: emailFromServer,
                            accessToken: accessToken, refreshToken: refreshToken)
        persist(s)
    }

    func signOut() {
        session = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    private func persist(_ s: AuthSession) {
        session = s
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    // MARK: - HTTP

    @discardableResult
    private func post(_ url: URL, apiKey: String, body: [String: Any], auth: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth ?? apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.errorMessage(from: data) ?? "Request failed (\(http.statusCode))."
            throw AuthError.badResponse(http.statusCode, msg)
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // GoTrue returns { "error_description": ... } or { "msg": ... } or { "message": ... }
        return (json["error_description"] as? String)
            ?? (json["msg"] as? String)
            ?? (json["message"] as? String)
    }
}
