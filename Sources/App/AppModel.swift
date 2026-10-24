import Foundation
import SwiftUI
import Combine

/// App-wide source of truth. Owns meals, profile, daily totals, and bridges to
/// the AI services. Views observe this.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile {
        didSet { PersistenceStore.saveProfile(profile) }
    }
    @Published var meals: [Meal] {
        didSet { PersistenceStore.saveMeals(meals) }
    }

    /// A meal that's been recognized but not yet confirmed/logged.
    @Published var pendingMeal: Meal?
    @Published var pendingCoachTip: String?
    @Published var isRecognizing = false
    @Published var recognitionNote: String?

    private let recognition = FoodRecognitionService()
    let coach = CoachService()

    /// Live sync with the web "wearable".
    let sync = SyncClient()
    /// IDs of synced sessions already logged, to avoid duplicates.
    private var loggedSyncIDs: Set<String> = []

    var aiConfigured: Bool { GroqClient.isConfigured }

    init() {
        self.profile = PersistenceStore.loadProfile()
        self.meals = PersistenceStore.loadMeals()

        // When the wearable ends a session, log it as a meal automatically.
        sync.onSessionEnded = { [weak self] session in
            self?.logSyncedSession(session)
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["NW_SEED"] == "1" {
            var p = self.profile; p.name = "Aaditya"; p.hasCompletedOnboarding = true
            p.recomputeTargetsIfNeeded(force: true); self.profile = p
        }
        if let c = ProcessInfo.processInfo.environment["NW_AUTOCONNECT"] {
            sync.configure(baseURL: "http://localhost:3000", code: c); sync.connect()
        }
        #endif
    }

    // MARK: - Daily aggregation

    func meals(on date: Date = Date()) -> [Meal] {
        let cal = Calendar.current
        return meals.filter { cal.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayTotals: Macros {
        meals(on: Date()).reduce(.zero) { $0 + $1.totals }
    }

    /// kcal per day for the last `days` days, oldest first (for the weekly chart).
    func weeklyCalories(days: Int = 7) -> [(date: Date, calories: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let cals = meals.filter { cal.isDate($0.timestamp, inSameDayAs: day) }
                .reduce(0) { $0 + $1.totals.calories }
            return (day, cals)
        }
    }

    // MARK: - Recognition flow

    func recognize(image: UIImage, mealType: String) async {
        isRecognizing = true
        recognitionNote = nil
        let result = await recognition.recognize(image: image)
        isRecognizing = false

        guard !result.items.isEmpty else {
            recognitionNote = result.note ?? "No food detected. Try getting the plate fully in frame."
            return
        }

        var meal = Meal(items: result.items, mealType: mealType)
        pendingMeal = meal
        recognitionNote = result.note

        // Kick off a proactive coaching tip for this plate.
        let context = coachContext(currentMeal: meal)
        pendingCoachTip = nil
        let tip = await coach.proactiveTip(for: context)
        // Only apply if still the same pending meal.
        if pendingMeal?.id == meal.id {
            pendingCoachTip = tip
            meal.coachNote = tip
            pendingMeal = meal
        }
    }

    /// Merge newly detected items into the pending meal, deduping by name.
    func mergeIntoPending(_ newItems: [FoodItem]) {
        guard var meal = pendingMeal else { return }
        let combined = FoodRecognitionService.dedupe(meal.items + newItems)
        meal.items = combined
        pendingMeal = meal
    }

    // MARK: - Live sync → meal log

    /// Convert an ended wearable session into a logged meal (idempotent).
    func logSyncedSession(_ session: SyncSession) {
        guard session.status == "ended", !session.items.isEmpty else { return }
        guard !loggedSyncIDs.contains(session.id),
              !meals.contains(where: { $0.syncID == session.id }) else { return }
        loggedSyncIDs.insert(session.id)

        let items: [FoodItem] = session.items.map { s in
            let conf = Confidence(rawValue: s.confidence.lowercased()) ?? .medium
            return FoodItem(
                name: s.name,
                portionDescription: s.portion,
                macros: Macros(calories: s.macros.calories, proteinG: s.macros.protein,
                               carbsG: s.macros.carbs, fatG: s.macros.fat),
                confidence: conf
            )
        }
        var meal = Meal(
            items: items,
            mealType: AppModel.suggestedMealType(for: session.startDate ?? Date())
        )
        meal.timestamp = session.startDate ?? Date()
        meal.durationSeconds = session.durationSeconds
        meal.coachNote = session.coachTip
        meal.syncID = session.id
        meal.startCalories = session.startCalories
        meal.leftoverCalories = session.leftoverCalories
        meals.insert(meal, at: 0)
    }

    // MARK: - Logging

    func confirmPendingMeal(durationSeconds: Int? = nil, consumedFraction: Double? = nil) {
        guard var meal = pendingMeal else { return }
        meal.durationSeconds = durationSeconds
        meal.consumedFraction = consumedFraction
        // Scale macros by how much was actually eaten, if estimated.
        if let fraction = consumedFraction, fraction < 0.999 {
            meal.items = meal.items.map { item in
                var copy = item
                copy.macros = item.macros.scaled(by: fraction)
                return copy
            }
        }
        meals.append(meal)
        pendingMeal = nil
        pendingCoachTip = nil
    }

    func discardPendingMeal() {
        pendingMeal = nil
        pendingCoachTip = nil
        recognitionNote = nil
    }

    func deleteMeal(_ meal: Meal) {
        meals.removeAll { $0.id == meal.id }
    }

    func updatePendingItem(_ item: FoodItem) {
        guard var meal = pendingMeal else { return }
        if let idx = meal.items.firstIndex(where: { $0.id == item.id }) {
            meal.items[idx] = item
            pendingMeal = meal
        }
    }

    func removePendingItem(_ item: FoodItem) {
        guard var meal = pendingMeal else { return }
        meal.items.removeAll { $0.id == item.id }
        pendingMeal = meal
    }

    // MARK: - Coach context

    func coachContext(currentMeal: Meal?, eatingDurationSeconds: Int? = nil) -> CoachService.Context {
        CoachService.Context(
            profile: profile,
            consumedToday: todayTotals,
            currentMeal: currentMeal,
            eatingDurationSeconds: eatingDurationSeconds
        )
    }

    func askCoach(_ question: String, currentMeal: Meal?, eatingDurationSeconds: Int?) async -> String {
        let ctx = coachContext(currentMeal: currentMeal, eatingDurationSeconds: eatingDurationSeconds)
        return await coach.answer(question: question, context: ctx)
    }

    // MARK: - Meal type helper

    static func suggestedMealType(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return "Breakfast"
        case 11..<16: return "Lunch"
        case 16..<22: return "Dinner"
        default: return "Snack"
        }
    }
}
