import Foundation

/// The real-time eating coach. Produces short, evidence-informed, nonjudgmental
/// guidance given the user's profile, today's intake, and the current meal.
struct CoachService {

    private static let systemPrompt = """
    You are NutriWear's real-time eating coach. You speak to the user WHILE they eat.

    Voice & style:
    - Warm, encouraging, nonjudgmental. Never shame food choices.
    - Short and actionable: 1-3 sentences unless asked for more.
    - Evidence-informed (satiety, protein, fiber, eating pace) but not preachy.
    - You are not a doctor; avoid medical claims and diagnosis.

    You get context: the user's goals/targets, what they've eaten today so far, \
    and the meal in front of them right now. Use it to personalize advice such as \
    which item to start with for fullness, whether the meal fits their remaining \
    budget, and simple balancing tips. Respect dietary preferences and allergies.
    """

    struct Context {
        var profile: UserProfile
        var consumedToday: Macros
        var currentMeal: Meal?
        var eatingDurationSeconds: Int?

        var remaining: Macros {
            Macros(
                calories: max(0, profile.dailyCalorieTarget - consumedToday.calories),
                proteinG: max(0, profile.dailyProteinTarget - consumedToday.proteinG),
                carbsG: max(0, profile.dailyCarbTarget - consumedToday.carbsG),
                fatG: max(0, profile.dailyFatTarget - consumedToday.fatG)
            )
        }

        var summary: String {
            var lines = [profile.coachContext]
            lines.append(String(
                format: "Eaten today: %.0f kcal, %.0fg protein, %.0fg carbs, %.0fg fat",
                consumedToday.calories, consumedToday.proteinG, consumedToday.carbsG, consumedToday.fatG
            ))
            lines.append(String(
                format: "Remaining today: %.0f kcal, %.0fg protein, %.0fg carbs, %.0fg fat",
                remaining.calories, remaining.proteinG, remaining.carbsG, remaining.fatG
            ))
            if let meal = currentMeal, !meal.items.isEmpty {
                let foods = meal.items.map { item -> String in
                    String(format: "%@ (%.0f kcal, %.0fg P)", item.name, item.macros.calories, item.macros.proteinG)
                }.joined(separator: "; ")
                lines.append("Meal in front of them now: \(foods)")
                lines.append(String(format: "This meal totals ~%.0f kcal.", meal.totals.calories))
            }
            if let d = eatingDurationSeconds {
                lines.append("They've been eating for \(d / 60)m \(d % 60)s.")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Personalized suggestions for improving eating habits, pace, and
    /// digestion, based on the user's logged-meal analytics. Returns 3-5 short
    /// bullet-style lines. Falls back to rule-based advice offline.
    func improvementSuggestions(profile: UserProfile, facts: String) async -> [String] {
        let user = """
        Based on the user's eating-habit data below, give 3-5 short, specific, \
        encouraging suggestions to improve their eating pace, meal timing, \
        digestion, and overall habits. Personalize to their goal and diet. \
        One sentence each. Return ONLY the suggestions, one per line, no numbering \
        or bullets.

        User:
        \(profile.coachContext)

        Eating-habit data:
        \(facts)
        """
        let fallback = Self.fallbackSuggestions(profile: profile).joined(separator: "\n")
        let text = await ask(user, context: Context(profile: profile, consumedToday: .zero,
                                                    currentMeal: nil, eatingDurationSeconds: nil),
                             fallback: fallback)
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^[\-\*\d\.\)\s]+"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    private static func fallbackSuggestions(profile: UserProfile) -> [String] {
        [
            "Slow meals to 20+ minutes — put your fork down between bites so fullness signals catch up.",
            "Start meals with protein or vegetables to feel satisfied on less.",
            "Keep roughly 4-5 hours between meals to avoid getting overly hungry.",
            "Finish eating a couple hours before bed to help digestion and sleep.",
            "Sip water through the meal; thirst often masquerades as hunger."
        ]
    }

    /// A proactive tip generated right after a meal is recognized.
    func proactiveTip(for context: Context) async -> String {
        let user = """
        Give ONE proactive coaching tip for the meal in front of me right now. \
        Mention which item to start with for fullness if relevant, and whether this \
        fits my remaining budget. Keep it to 1-2 sentences.

        Context:
        \(context.summary)
        """
        return await ask(user, context: context, fallback: Self.fallbackTip(context))
    }

    /// A short, personalized proactive cue to deliver mid-meal (spoken or
    /// notified). `pace` describes how fast the meal is going so the model can
    /// be specific. Falls back to a local line when AI is unavailable.
    func cueMessage(for cue: CoachCue, context: Context, pace: PaceSnapshot) async -> String {
        let user = """
        Generate ONE very short proactive coaching line (max ~18 words) to say to \
        the user WHILE they eat. Cue type: \(cue.rawValue).
        Guidance for this cue: \(cue.detail).
        Be warm, specific, and personalized to their meal and pace. No preamble, \
        no quotes — just the line.

        Live pace: \(pace.description)
        Context:
        \(context.summary)
        """
        return await ask(user, context: context, fallback: Self.fallbackCue(cue, context, pace))
    }

    /// Answer a free-form user question (voice or text).
    func answer(question: String, context: Context) async -> String {
        let user = """
        The user asked: "\(question)"

        Answer directly and briefly using the context below. If they ask how much \
        of a macro they have left, use the remaining numbers.

        Context:
        \(context.summary)
        """
        return await ask(user, context: context, fallback: Self.fallbackAnswer(question, context))
    }

    private func ask(_ userText: String, context: Context, fallback: String) async -> String {
        guard GroqClient.isConfigured else { return fallback }
        do {
            let reply = try await GroqClient.shared.complete(
                model: GroqModel.text,
                messages: [.system(Self.systemPrompt), .user(userText)],
                temperature: 0.6,
                maxTokens: 300
            )
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        } catch {
            return fallback
        }
    }

    /// A compact description of eating pace for proactive cues.
    struct PaceSnapshot {
        var elapsedSeconds: Int
        var mealCalories: Double
        /// 0...1 fraction of the meal consumed, if known (web before/after).
        var consumedFraction: Double?

        /// kcal per minute (rough intensity of eating).
        var kcalPerMinute: Double {
            let mins = max(0.25, Double(elapsedSeconds) / 60.0)
            let eaten = (consumedFraction ?? 1.0) * mealCalories
            return eaten / mins
        }

        /// Heuristic: a sizeable meal disappearing very quickly.
        var isTooFast: Bool {
            elapsedSeconds < 6 * 60 && mealCalories > 400 && kcalPerMinute > 90
        }

        var description: String {
            var s = "elapsed \(elapsedSeconds / 60)m \(elapsedSeconds % 60)s, meal ~\(Int(mealCalories)) kcal"
            if let f = consumedFraction { s += ", ~\(Int(f * 100))% eaten" }
            s += String(format: ", ~%.0f kcal/min", kcalPerMinute)
            return s
        }
    }

    private static func fallbackCue(_ cue: CoachCue, _ context: Context, _ pace: PaceSnapshot) -> String {
        let name = context.profile.name == "there" ? "" : " \(context.profile.name)"
        switch cue {
        case .slowDown:
            return "Ease up a touch\(name) — that plate's going fast. Set the fork down for a breath between bites."
        case .halfwayCheck:
            return "Halfway there. Check in: are you still genuinely hungry, or eating on autopilot?"
        case .startReminder:
            return "Got it — I'm watching this meal. Say \"I'm done\" when you finish."
        case .finishSummary:
            let mins = pace.elapsedSeconds / 60
            return mins >= 15
                ? "Nice, well-paced meal at \(mins) min. That gives fullness time to land."
                : "Logged. That was quick at \(mins) min — next time try stretching it past 15."
        case .hydration:
            return "Sip some water between bites — it helps you notice fullness sooner."
        }
    }

    // MARK: - Offline fallbacks (labeled, still useful)

    private static func fallbackTip(_ context: Context) -> String {
        guard let meal = context.currentMeal, !meal.items.isEmpty else {
            return "Add a Groq key for live coaching. Tip: start meals with protein or veggies to feel full sooner."
        }
        let highestProtein = meal.items.max(by: { $0.macros.proteinG < $1.macros.proteinG })
        let veg = meal.items.first { $0.name.lowercased().contains("broccoli") || $0.name.lowercased().contains("salad") || $0.name.lowercased().contains("veg") }
        let start = veg ?? highestProtein
        let fits = meal.totals.calories <= context.remaining.calories
        let budget = fits ? "This fits your remaining calories today." : "This runs a bit over your remaining calories, so consider a lighter portion."
        if let start {
            return "Start with the \(start.name.lowercased()) to feel fuller sooner. \(budget)"
        }
        return budget
    }

    private static func fallbackAnswer(_ question: String, _ context: Context) -> String {
        let q = question.lowercased()
        let r = context.remaining
        if q.contains("protein") {
            return String(format: "You have about %.0f g of protein left for today.", r.proteinG)
        }
        if q.contains("carb") {
            return String(format: "About %.0f g of carbs remaining today.", r.carbsG)
        }
        if q.contains("fat") {
            return String(format: "About %.0f g of fat remaining today.", r.fatG)
        }
        if q.contains("calorie") || q.contains("left") {
            return String(format: "You have roughly %.0f kcal remaining today.", r.calories)
        }
        if q.contains("eating") && (q.contains("fast") || q.contains("slow") || q.contains("pace")) {
            if let d = context.eatingDurationSeconds {
                let mins = Double(d) / 60.0
                return mins < 10
                    ? "You're at \(Int(mins)) min. Meals under ~20 min can feel rushed. Try setting the fork down between bites."
                    : "Nice pace. You've been going \(Int(mins)) min, which gives your body time to register fullness."
            }
            return "Start the meal timer and I can tell you if you're eating too fast."
        }
        if q.contains("what") && q.contains("eat") {
            if let meal = context.currentMeal, !meal.items.isEmpty {
                return "You're eating " + meal.items.map { $0.name.lowercased() }.joined(separator: ", ") + "."
            }
            return "Scan a meal first and I'll tell you what's on your plate."
        }
        return "Add a Groq key for full answers. For now: you have about \(Int(r.calories)) kcal and \(Int(r.proteinG)) g protein left today."
    }
}
