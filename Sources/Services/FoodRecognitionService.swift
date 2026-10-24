import Foundation
import UIKit

/// Turns a plate photo into structured, deduplicated food items using Groq vision.
struct FoodRecognitionService {

    /// Result of a recognition pass.
    struct Result {
        var items: [FoodItem]
        var usedLiveAI: Bool      // false => offline/mock fallback
        var note: String?         // optional model commentary
    }

    private static let systemPrompt = """
    You are NutriWear's food vision engine. You look at a photo of a plate/meal and \
    return a strict JSON object describing the distinct foods you see.

    Rules:
    - Only report foods you can actually see. Do not invent items.
    - Merge duplicates: if you see one plate of pasta, that's ONE item, not many.
    - Estimate realistic portion sizes from visual cues (plate size, utensils).
    - Nutrition numbers are approximate; set confidence accordingly.
    - If the image has no food, return an empty items array.

    Return ONLY this JSON shape (no markdown, no prose):
    {
      "items": [
        {
          "name": "string",
          "portion": "short human portion estimate, e.g. 'about 1 cup'",
          "calories": number,
          "protein_g": number,
          "carbs_g": number,
          "fat_g": number,
          "confidence": "high" | "medium" | "low",
          "ingredients": ["string", ...]
        }
      ],
      "note": "one short sentence or empty string"
    }
    """

    /// Recognize foods in a captured image.
    func recognize(image: UIImage) async -> Result {
        guard GroqClient.isConfigured, let dataURL = Self.jpegDataURL(from: image) else {
            return Self.offlineResult(reason: GroqClient.isConfigured ? "image encode failed" : "no API key")
        }

        let messages: [ChatMessage] = [
            .system(Self.systemPrompt),
            .userImage(
                prompt: "Identify the distinct foods in this meal and estimate nutrition. Return only the JSON object.",
                imageDataURL: dataURL
            )
        ]

        do {
            let raw = try await GroqClient.shared.complete(
                model: GroqModel.vision,
                messages: messages,
                temperature: 0.2,
                maxTokens: 1200,
                jsonMode: true
            )
            let items = try Self.parse(raw)
            let note = Self.extractNote(raw)
            return Result(items: Self.dedupe(items), usedLiveAI: true, note: note)
        } catch {
            return Self.offlineResult(reason: error.localizedDescription)
        }
    }

    // MARK: - JSON parsing

    private static func parse(_ raw: String) throws -> [FoodItem] {
        guard let data = extractJSONObject(raw).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = obj["items"] as? [[String: Any]] else {
            throw GroqError.decoding("Could not find items array")
        }

        return rawItems.compactMap { dict in
            guard let name = dict["name"] as? String, !name.isEmpty else { return nil }
            let macros = Macros(
                calories: doubleValue(dict["calories"]),
                proteinG: doubleValue(dict["protein_g"]),
                carbsG: doubleValue(dict["carbs_g"]),
                fatG: doubleValue(dict["fat_g"])
            )
            let conf = Confidence(rawValue: (dict["confidence"] as? String ?? "medium").lowercased()) ?? .medium
            let ingredients = (dict["ingredients"] as? [String]) ?? []
            return FoodItem(
                name: name,
                portionDescription: (dict["portion"] as? String) ?? "estimated portion",
                macros: macros,
                confidence: conf,
                ingredients: ingredients
            )
        }
    }

    private static func extractNote(_ raw: String) -> String? {
        guard let data = extractJSONObject(raw).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let note = obj["note"] as? String,
              !note.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return note
    }

    /// Pulls the first {...} block out of a response in case the model wraps it.
    private static func extractJSONObject(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end else { return raw }
        return String(raw[start...end])
    }

    private static func doubleValue(_ any: Any?) -> Double {
        if let d = any as? Double { return max(0, d) }
        if let i = any as? Int { return max(0, Double(i)) }
        if let s = any as? String, let d = Double(s) { return max(0, d) }
        return 0
    }

    // MARK: - Dedupe

    /// Collapse items with near-identical names (case-insensitive) so one plate
    /// scanned twice doesn't double-log.
    static func dedupe(_ items: [FoodItem]) -> [FoodItem] {
        var seen: [String: FoodItem] = [:]
        var order: [String] = []
        for item in items {
            let key = item.name.lowercased().trimmingCharacters(in: .whitespaces)
            if seen[key] == nil {
                seen[key] = item
                order.append(key)
            }
        }
        return order.compactMap { seen[$0] }
    }

    // MARK: - Encoding

    static func jpegDataURL(from image: UIImage, maxDimension: CGFloat = 1024) -> String? {
        let resized = resize(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.6) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Offline fallback

    /// A clearly-labeled sample result so the app is demoable without a key.
    private static func offlineResult(reason: String) -> Result {
        let items = [
            FoodItem(
                name: "Grilled chicken breast",
                portionDescription: "about 150 g",
                macros: Macros(calories: 240, proteinG: 45, carbsG: 0, fatG: 6),
                confidence: .medium,
                ingredients: ["chicken", "olive oil", "pepper"]
            ),
            FoodItem(
                name: "Brown rice",
                portionDescription: "about 1 cup",
                macros: Macros(calories: 215, proteinG: 5, carbsG: 45, fatG: 2),
                confidence: .medium,
                ingredients: ["brown rice"]
            ),
            FoodItem(
                name: "Steamed broccoli",
                portionDescription: "about 1 cup",
                macros: Macros(calories: 55, proteinG: 4, carbsG: 11, fatG: 1),
                confidence: .medium,
                ingredients: ["broccoli"]
            )
        ]
        return Result(items: items, usedLiveAI: false,
                      note: "Offline sample (\(reason)). Add a Groq key for live recognition.")
    }
}
