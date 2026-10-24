import Foundation
import UIKit

/// Stretch goal: compare a before/after plate photo to estimate how much food
/// was eaten. This is explicitly approximate — we ask the vision model to judge
/// the visible reduction in food, and we clearly label the uncertainty.
enum ConsumptionEstimator {

    struct Estimate {
        var fraction: Double   // 0...1 portion eaten
        var note: String
    }

    private static let systemPrompt = """
    You compare two photos of the SAME plate: the first BEFORE eating and the \
    second AFTER. Estimate roughly what fraction of the food was eaten, judging \
    only by visible reduction in food volume. This is approximate — do not claim \
    precision. Return ONLY JSON:
    {"fraction_eaten": number between 0 and 1, "note": "one short caveat sentence"}
    """

    static func estimate(before: UIImage, after: UIImage) async -> Estimate {
        guard GroqClient.isConfigured,
              let beforeURL = FoodRecognitionService.jpegDataURL(from: before, maxDimension: 768),
              let afterURL = FoodRecognitionService.jpegDataURL(from: after, maxDimension: 768) else {
            return Estimate(fraction: 0.6, note: "Offline estimate (~60%). Add a Groq key for a visual comparison.")
        }

        // Send both images in one user message.
        let messages: [ChatMessage] = [
            .system(systemPrompt),
            .init(role: "user", content: .text("First image = BEFORE, second = AFTER. Compare them.")),
            .userImage(prompt: "BEFORE:", imageDataURL: beforeURL),
            .userImage(prompt: "AFTER:", imageDataURL: afterURL)
        ]

        do {
            let raw = try await GroqClient.shared.complete(
                model: GroqModel.vision,
                messages: messages,
                temperature: 0.2,
                maxTokens: 300,
                jsonMode: true
            )
            if let data = extractJSON(raw).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let fraction = clamp(doubleValue(obj["fraction_eaten"]))
                let note = (obj["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Approximate visual estimate."
                return Estimate(fraction: fraction, note: "≈\(Int(fraction * 100))% eaten (approx). \(note)")
            }
            return Estimate(fraction: 0.6, note: "Couldn't parse estimate; assumed ~60%.")
        } catch {
            return Estimate(fraction: 0.6, note: "Estimate failed (\(error.localizedDescription)). Assumed ~60%.")
        }
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    private static func doubleValue(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String, let d = Double(s) { return d }
        return 0.6
    }

    private static func extractJSON(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end else { return raw }
        return String(raw[start...end])
    }
}
