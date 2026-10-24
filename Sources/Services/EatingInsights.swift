import Foundation

/// Analytics over logged meals: eating pace, habits, timing, and digestion
/// signals. Pure functions over `[Meal]` so they're easy to test and cheap to
/// recompute. The AI layer turns these facts into personalized suggestions.
struct EatingInsights {

    // MARK: - Metrics

    /// Meals that recorded an eating duration.
    let timedMeals: [Meal]
    let allMeals: [Meal]

    init(meals: [Meal]) {
        self.allMeals = meals
        self.timedMeals = meals.filter { ($0.durationSeconds ?? 0) > 0 }
    }

    /// Average meal duration in minutes across meals that were timed.
    var averageDurationMinutes: Double? {
        guard !timedMeals.isEmpty else { return nil }
        let total = timedMeals.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        return Double(total) / Double(timedMeals.count) / 60.0
    }

    /// Fraction of timed meals eaten "too fast" (under 10 minutes).
    var fastMealRate: Double? {
        guard !timedMeals.isEmpty else { return nil }
        let fast = timedMeals.filter { ($0.durationSeconds ?? 0) < 10 * 60 }.count
        return Double(fast) / Double(timedMeals.count)
    }

    /// Meals eaten late (after 9pm), which can affect digestion/sleep.
    var lateNightMealCount: Int {
        let cal = Calendar.current
        return allMeals.filter { cal.component(.hour, from: $0.timestamp) >= 21 }.count
    }

    /// Average gap between meals in hours (within the same day).
    var averageMealGapHours: Double? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: allMeals) { cal.startOfDay(for: $0.timestamp) }
        var gaps: [Double] = []
        for (_, dayMeals) in byDay {
            let sorted = dayMeals.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 2 else { continue }
            for i in 1..<sorted.count {
                gaps.append(sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp) / 3600)
            }
        }
        guard !gaps.isEmpty else { return nil }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    /// Average leftover fraction, where before/after estimates exist (how much
    /// of served food is typically left — a portion-sizing signal).
    var averageLeftoverFraction: Double? {
        let withData = allMeals.compactMap { meal -> Double? in
            guard let start = meal.startCalories, start > 0,
                  let leftover = meal.leftoverCalories else { return nil }
            return min(1, max(0, leftover / start))
        }
        guard !withData.isEmpty else { return nil }
        return withData.reduce(0, +) / Double(withData.count)
    }

    /// Protein as a share of calories across all logged meals (0...1).
    var proteinShareOfCalories: Double? {
        let totals = allMeals.reduce(Macros.zero) { $0 + $1.totals }
        guard totals.calories > 0 else { return nil }
        return (totals.proteinG * 4.0) / totals.calories
    }

    // MARK: - Headline cards (rule-based, always available)

    struct HabitCard: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tone: Tone
        enum Tone { case positive, warning, neutral }
    }

    /// Rule-based habit observations. These work offline and seed the AI prompt.
    var habitCards: [HabitCard] {
        var cards: [HabitCard] = []

        if let avg = averageDurationMinutes {
            if avg < 10 {
                cards.append(.init(icon: "hare.fill", title: "You eat quickly",
                    detail: String(format: "Your meals average %.0f min. Aiming for 20+ gives fullness signals time to catch up.", avg),
                    tone: .warning))
            } else if avg >= 18 {
                cards.append(.init(icon: "tortoise.fill", title: "Well-paced meals",
                    detail: String(format: "You average %.0f min per meal — great for digestion and satiety.", avg),
                    tone: .positive))
            } else {
                cards.append(.init(icon: "fork.knife", title: "Moderate pace",
                    detail: String(format: "You average %.0f min per meal. A few more minutes would help even more.", avg),
                    tone: .neutral))
            }
        }

        if let rate = fastMealRate, rate >= 0.5, timedMeals.count >= 2 {
            cards.append(.init(icon: "gauge.high", title: "Rushed meals add up",
                detail: "\(Int(rate * 100))% of your timed meals were under 10 minutes. Slowing down aids digestion.",
                tone: .warning))
        }

        if lateNightMealCount >= 3 {
            cards.append(.init(icon: "moon.stars.fill", title: "Late-night eating",
                detail: "\(lateNightMealCount) meals logged after 9pm. Earlier dinners can improve sleep and digestion.",
                tone: .warning))
        }

        if let gap = averageMealGapHours {
            if gap > 6 {
                cards.append(.init(icon: "clock.badge.exclamationmark", title: "Long gaps between meals",
                    detail: String(format: "You go about %.1f h between meals, which can drive overeating later.", gap),
                    tone: .warning))
            } else {
                cards.append(.init(icon: "clock.fill", title: "Steady meal timing",
                    detail: String(format: "About %.1f h between meals — a consistent rhythm.", gap),
                    tone: .positive))
            }
        }

        if let protein = proteinShareOfCalories {
            if protein < 0.20 {
                cards.append(.init(icon: "bolt.heart.fill", title: "Room for more protein",
                    detail: "Protein is \(Int(protein * 100))% of your calories. Lifting it toward 25-30% boosts fullness.",
                    tone: .neutral))
            } else {
                cards.append(.init(icon: "bolt.heart.fill", title: "Solid protein intake",
                    detail: "Protein is \(Int(protein * 100))% of your calories — good for satiety and muscle.",
                    tone: .positive))
            }
        }

        if cards.isEmpty {
            cards.append(.init(icon: "sparkles", title: "Keep logging",
                detail: "Log and time a few meals and I'll surface patterns in your pace, timing, and habits.",
                tone: .neutral))
        }
        return cards
    }

    /// A compact fact sheet handed to the LLM for personalized suggestions.
    var factSheet: String {
        var lines: [String] = []
        lines.append("Meals logged: \(allMeals.count) (timed: \(timedMeals.count))")
        if let avg = averageDurationMinutes { lines.append(String(format: "Avg meal duration: %.1f min", avg)) }
        if let rate = fastMealRate { lines.append("Meals under 10 min: \(Int(rate * 100))%") }
        if lateNightMealCount > 0 { lines.append("Meals after 9pm: \(lateNightMealCount)") }
        if let gap = averageMealGapHours { lines.append(String(format: "Avg gap between meals: %.1f h", gap)) }
        if let lo = averageLeftoverFraction { lines.append("Avg food left on plate: \(Int(lo * 100))%") }
        if let p = proteinShareOfCalories { lines.append("Protein share of calories: \(Int(p * 100))%") }
        return lines.joined(separator: "\n")
    }
}
