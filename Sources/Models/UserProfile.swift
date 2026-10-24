import Foundation

enum PrimaryGoal: String, Codable, CaseIterable, Identifiable {
    case loseFat = "Lose fat"
    case maintain = "Maintain"
    case buildMuscle = "Build muscle"
    case eatHealthier = "Eat healthier"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .loseFat: return "Moderate calorie deficit"
        case .maintain: return "Stay at your current weight"
        case .buildMuscle: return "Lean calorie surplus"
        case .eatHealthier: return "Balanced, around maintenance"
        }
    }

    var icon: String {
        switch self {
        case .loseFat: return "flame.fill"
        case .maintain: return "equal.circle.fill"
        case .buildMuscle: return "dumbbell.fill"
        case .eatHealthier: return "leaf.fill"
        }
    }
}

enum DietPreference: String, Codable, CaseIterable, Identifiable {
    case none = "No preference"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case pescatarian = "Pescatarian"
    case keto = "Keto / low-carb"
    case glutenFree = "Gluten-free"

    var id: String { rawValue }
}

/// Everything the coach needs to personalize advice.
struct UserProfile: Codable, Equatable {
    var name: String

    // TDEE inputs
    var sex: BiologicalSex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var activity: ActivityLevel

    var goal: PrimaryGoal
    var diet: DietPreference
    var allergies: String

    // Targets (auto-computed, user-adjustable)
    var dailyCalorieTarget: Double
    var dailyProteinTarget: Double
    var dailyCarbTarget: Double
    var dailyFatTarget: Double
    var targetsManuallyEdited: Bool

    var slowEatingReminders: Bool
    var hasCompletedOnboarding: Bool

    /// Proactive-coaching settings (delivery channel + which cues fire).
    var coaching: CoachingPreferences = .default

    static let `default` = UserProfile(
        name: "there",
        sex: .male,
        age: 28,
        heightCm: 175,
        weightKg: 72,
        activity: .moderate,
        goal: .eatHealthier,
        diet: .none,
        allergies: "",
        dailyCalorieTarget: 2200,
        dailyProteinTarget: 140,
        dailyCarbTarget: 230,
        dailyFatTarget: 70,
        targetsManuallyEdited: false,
        slowEatingReminders: true,
        hasCompletedOnboarding: false
    )

    // Backward-compatible decoding: profiles saved before `coaching` existed
    // decode with the default coaching preferences instead of failing.
    private enum CodingKeys: String, CodingKey {
        case name, sex, age, heightCm, weightKg, activity, goal, diet, allergies
        case dailyCalorieTarget, dailyProteinTarget, dailyCarbTarget, dailyFatTarget
        case targetsManuallyEdited, slowEatingReminders, hasCompletedOnboarding, coaching
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sex = try c.decode(BiologicalSex.self, forKey: .sex)
        age = try c.decode(Int.self, forKey: .age)
        heightCm = try c.decode(Double.self, forKey: .heightCm)
        weightKg = try c.decode(Double.self, forKey: .weightKg)
        activity = try c.decode(ActivityLevel.self, forKey: .activity)
        goal = try c.decode(PrimaryGoal.self, forKey: .goal)
        diet = try c.decode(DietPreference.self, forKey: .diet)
        allergies = try c.decode(String.self, forKey: .allergies)
        dailyCalorieTarget = try c.decode(Double.self, forKey: .dailyCalorieTarget)
        dailyProteinTarget = try c.decode(Double.self, forKey: .dailyProteinTarget)
        dailyCarbTarget = try c.decode(Double.self, forKey: .dailyCarbTarget)
        dailyFatTarget = try c.decode(Double.self, forKey: .dailyFatTarget)
        targetsManuallyEdited = try c.decode(Bool.self, forKey: .targetsManuallyEdited)
        slowEatingReminders = try c.decode(Bool.self, forKey: .slowEatingReminders)
        hasCompletedOnboarding = try c.decode(Bool.self, forKey: .hasCompletedOnboarding)
        coaching = try c.decodeIfPresent(CoachingPreferences.self, forKey: .coaching) ?? .default
    }

    // Keep the memberwise initializer available (used by `.default`). Declaring
    // it explicitly is required once we add a custom `init(from:)`.
    init(
        name: String, sex: BiologicalSex, age: Int, heightCm: Double, weightKg: Double,
        activity: ActivityLevel, goal: PrimaryGoal, diet: DietPreference, allergies: String,
        dailyCalorieTarget: Double, dailyProteinTarget: Double, dailyCarbTarget: Double,
        dailyFatTarget: Double, targetsManuallyEdited: Bool, slowEatingReminders: Bool,
        hasCompletedOnboarding: Bool, coaching: CoachingPreferences = .default
    ) {
        self.name = name; self.sex = sex; self.age = age
        self.heightCm = heightCm; self.weightKg = weightKg; self.activity = activity
        self.goal = goal; self.diet = diet; self.allergies = allergies
        self.dailyCalorieTarget = dailyCalorieTarget; self.dailyProteinTarget = dailyProteinTarget
        self.dailyCarbTarget = dailyCarbTarget; self.dailyFatTarget = dailyFatTarget
        self.targetsManuallyEdited = targetsManuallyEdited
        self.slowEatingReminders = slowEatingReminders
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.coaching = coaching
    }

    var dailyTargets: Macros {
        Macros(calories: dailyCalorieTarget, proteinG: dailyProteinTarget,
               carbsG: dailyCarbTarget, fatG: dailyFatTarget)
    }

    var tdeeInputs: TDEECalculator.Inputs {
        .init(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
              activity: activity, goal: goal)
    }

    /// Recompute targets from TDEE unless the user hand-edited them.
    mutating func recomputeTargetsIfNeeded(force: Bool = false) {
        guard force || !targetsManuallyEdited else { return }
        let out = TDEECalculator.compute(tdeeInputs)
        dailyCalorieTarget = out.macros.calories
        dailyProteinTarget = out.macros.proteinG
        dailyCarbTarget = out.macros.carbsG
        dailyFatTarget = out.macros.fatG
    }

    /// Compact context string handed to the LLM coach.
    var coachContext: String {
        var parts: [String] = []
        parts.append("Name: \(name)")
        parts.append("Profile: \(sex.rawValue), age \(age), \(Int(heightCm)) cm, \(Int(weightKg)) kg, \(activity.rawValue)")
        parts.append("Goal: \(goal.rawValue)")
        parts.append("Diet: \(diet.rawValue)")
        if !allergies.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("Allergies/avoids: \(allergies)")
        }
        parts.append(String(format: "Daily targets: %.0f kcal, %.0fg protein, %.0fg carbs, %.0fg fat",
                            dailyCalorieTarget, dailyProteinTarget, dailyCarbTarget, dailyFatTarget))
        return parts.joined(separator: "\n")
    }
}
