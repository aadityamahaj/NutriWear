import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    var id: String { rawValue }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light = "Lightly active"
    case moderate = "Moderately active"
    case active = "Very active"
    case athlete = "Athlete"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .athlete: return 1.9
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Little or no exercise, desk job"
        case .light: return "Light exercise 1–3 days/week"
        case .moderate: return "Moderate exercise 3–5 days/week"
        case .active: return "Hard exercise 6–7 days/week"
        case .athlete: return "Intense training / physical job"
        }
    }
}

/// Computes BMR (Mifflin-St Jeor), TDEE, and goal-adjusted macro targets.
enum TDEECalculator {

    struct Inputs {
        var sex: BiologicalSex
        var age: Int
        var heightCm: Double
        var weightKg: Double
        var activity: ActivityLevel
        var goal: PrimaryGoal
    }

    struct Output {
        var bmr: Double
        var tdee: Double
        var targetCalories: Double
        var macros: Macros
    }

    /// Mifflin-St Jeor basal metabolic rate.
    static func bmr(_ i: Inputs) -> Double {
        let base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * Double(i.age)
        return i.sex == .male ? base + 5 : base - 161
    }

    static func compute(_ i: Inputs) -> Output {
        let bmr = bmr(i)
        let tdee = bmr * i.activity.multiplier

        // Goal-based calorie adjustment.
        let target: Double
        switch i.goal {
        case .loseFat:      target = tdee - 450   // moderate deficit
        case .maintain:     target = tdee
        case .eatHealthier: target = tdee
        case .buildMuscle:  target = tdee + 300   // lean surplus
        }
        let calories = max(1200, target.rounded())

        return Output(bmr: bmr.rounded(), tdee: tdee.rounded(),
                      targetCalories: calories, macros: macros(for: calories, goal: i.goal, weightKg: i.weightKg))
    }

    /// Macro split tuned by goal. Protein anchored to bodyweight, rest split by calories.
    static func macros(for calories: Double, goal: PrimaryGoal, weightKg: Double) -> Macros {
        // Protein grams per kg bodyweight.
        let proteinPerKg: Double
        switch goal {
        case .buildMuscle: proteinPerKg = 2.0
        case .loseFat:     proteinPerKg = 2.0
        case .maintain:    proteinPerKg = 1.6
        case .eatHealthier: proteinPerKg = 1.6
        }
        let proteinG = (proteinPerKg * weightKg).rounded()
        let proteinCal = proteinG * 4

        // Fat ~27% of calories.
        let fatCal = calories * 0.27
        let fatG = (fatCal / 9).rounded()

        // Remainder to carbs.
        let carbCal = max(0, calories - proteinCal - fatCal)
        let carbsG = (carbCal / 4).rounded()

        return Macros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}
