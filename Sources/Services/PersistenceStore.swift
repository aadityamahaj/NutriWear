import Foundation

/// Lightweight JSON-on-UserDefaults persistence. No backend, mirrors a
/// localStorage approach. All reads/writes happen on the main actor via AppModel.
enum PersistenceStore {
    private static let mealsKey = "nutriwear.meals.v1"
    private static let profileKey = "nutriwear.profile.v1"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func loadMeals() -> [Meal] {
        guard let data = UserDefaults.standard.data(forKey: mealsKey),
              let meals = try? decoder.decode([Meal].self, from: data) else {
            return []
        }
        return meals
    }

    static func saveMeals(_ meals: [Meal]) {
        if let data = try? encoder.encode(meals) {
            UserDefaults.standard.set(data, forKey: mealsKey)
        }
    }

    static func loadProfile() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let profile = try? decoder.decode(UserProfile.self, from: data) else {
            return .default
        }
        return profile
    }

    static func saveProfile(_ profile: UserProfile) {
        if let data = try? encoder.encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }
}
