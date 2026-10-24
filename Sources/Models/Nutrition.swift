import Foundation

/// Macronutrient breakdown in grams plus calories.
struct Macros: Codable, Hashable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    static let zero = Macros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG
        )
    }

    func scaled(by factor: Double) -> Macros {
        Macros(
            calories: calories * factor,
            proteinG: proteinG * factor,
            carbsG: carbsG * factor,
            fatG: fatG * factor
        )
    }
}

/// How confident the vision model is about a detection.
enum Confidence: String, Codable, CaseIterable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Rough estimate"
        case .low: return "Uncertain"
        }
    }
}

/// A single recognized food item within a meal.
struct FoodItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var portionDescription: String   // e.g. "about 1 cup", "~150 g"
    var macros: Macros
    var confidence: Confidence
    var ingredients: [String]

    init(
        id: UUID = UUID(),
        name: String,
        portionDescription: String,
        macros: Macros,
        confidence: Confidence,
        ingredients: [String] = []
    ) {
        self.id = id
        self.name = name
        self.portionDescription = portionDescription
        self.macros = macros
        self.confidence = confidence
        self.ingredients = ingredients
    }
}

/// A logged (or pending) meal: a set of food items plus behavior data.
struct Meal: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var items: [FoodItem]
    var mealType: String          // Breakfast / Lunch / Dinner / Snack
    var durationSeconds: Int?     // from the eating timer, if used
    var consumedFraction: Double? // 0...1 estimate from before/after, if available
    var coachNote: String?        // one-line coaching summary captured at log time
    var syncID: String?           // id of the originating wearable session, if synced
    var startCalories: Double?    // total on the plate at start (before/after story)
    var leftoverCalories: Double? // left on the plate at the end

    var totals: Macros {
        items.reduce(.zero) { $0 + $1.macros }
    }

    var title: String {
        if items.isEmpty { return "Empty meal" }
        if items.count == 1 { return items[0].name }
        return "\(items[0].name) + \(items.count - 1) more"
    }
}
