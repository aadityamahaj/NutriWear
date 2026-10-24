import Foundation
import SwiftUI

/// Mirrors the web app's sync types so the phone can decode the SSE stream.
struct SyncFoodItem: Codable, Hashable {
    struct M: Codable, Hashable { var calories: Double; var protein: Double; var carbs: Double; var fat: Double }
    var name: String
    var portion: String
    var macros: M
    var confidence: String
}

struct SyncSession: Codable, Identifiable, Hashable {
    var id: String
    var status: String          // idle | eating | ended
    var startedAt: Double?      // epoch ms
    var endedAt: Double?        // epoch ms
    var detectedBy: String?
    var items: [SyncFoodItem]
    var coachTip: String?
    var usedLiveAI: Bool?
    var note: String?
    // Before/after consumption estimate (from /api/compare)
    var startCalories: Double?
    var eatenCalories: Double?
    var leftoverCalories: Double?

    var startDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var endDate: Date? { endedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var durationSeconds: Int? {
        guard let s = startedAt, let e = endedAt else { return nil }
        return Int((e - s) / 1000)
    }
}

struct SyncChannelState: Codable {
    var code: String
    var current: SyncSession?
    var history: [SyncSession]
    var updatedAt: Double
}

/// Connects the phone (companion) to the web app's live sync stream (SSE).
/// Set the base URL to the Mac running `npm run dev`, e.g. http://192.168.1.20:3000
@MainActor
final class SyncClient: ObservableObject {
    @Published var connected = false
    @Published var current: SyncSession?
    @Published var history: [SyncSession] = []
    @Published var lastError: String?

    /// Called when a session ends, so AppModel can log the meal.
    var onSessionEnded: ((SyncSession) -> Void)?

    private var task: Task<Void, Never>?
    private(set) var baseURL: String = UserDefaults.standard.string(forKey: "nutriwear.sync.url") ?? "http://localhost:3000"
    private(set) var code: String = UserDefaults.standard.string(forKey: "nutriwear.sync.code") ?? ""

    func configure(baseURL: String, code: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        self.code = code.uppercased().trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(self.baseURL, forKey: "nutriwear.sync.url")
        UserDefaults.standard.set(self.code, forKey: "nutriwear.sync.code")
    }

    func connect() {
        disconnect()
        guard !code.isEmpty, let url = URL(string: "\(baseURL)/api/stream?code=\(code)") else {
            lastError = "Enter a valid server URL and pairing code."
            return
        }
        lastError = nil
        task = Task { await streamLoop(url: url) }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        connected = false
    }

    private func streamLoop(url: URL) async {
        while !Task.isCancelled {
            do {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 3600

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                connected = true
                lastError = nil

                // SSE: lines beginning with "data: " carry JSON payloads.
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data:") else { continue }
                    let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard let data = json.data(using: .utf8) else { continue }
                    handleEvent(data)
                }
            } catch {
                connected = false
                if !Task.isCancelled {
                    lastError = "Disconnected. Retrying…"
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    private func handleEvent(_ data: Data) {
        // Events are tagged by "type". Decode loosely.
        struct Envelope: Codable { var type: String }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }

        switch env.type {
        case "state":
            struct E: Codable { var state: SyncChannelState }
            if let e = try? JSONDecoder().decode(E.self, from: data) {
                current = e.state.current
                history = e.state.history
            }
        case "session.started", "session.updated":
            struct E: Codable { var session: SyncSession }
            if let e = try? JSONDecoder().decode(E.self, from: data) {
                current = e.session
            }
        case "session.ended":
            struct E: Codable { var session: SyncSession }
            if let e = try? JSONDecoder().decode(E.self, from: data) {
                current = e.session
                if !history.contains(where: { $0.id == e.session.id }) {
                    history.insert(e.session, at: 0)
                }
                onSessionEnded?(e.session)
            }
        default:
            break
        }
    }
}
