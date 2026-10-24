import Foundation

/// A live, in-progress eating session on the phone. Distinct from the web
/// `SyncSession` (which arrives already completed). This drives the proactive
/// coach and the hands-free timer.
struct ActiveEatingSession: Identifiable, Equatable {
    let id = UUID()
    var startedAt: Date
    /// The recognized meal being eaten, if a scan happened. May be nil for a
    /// voice-started session with no photo yet.
    var meal: Meal?
    var paused: Bool = false
    /// Accumulated eating seconds (excludes paused time).
    var elapsedSeconds: Int = 0
    /// How the session began.
    var startedBy: StartSource

    enum StartSource: String { case voice, manual, auto, scan }

    var mealCalories: Double { meal?.totals.calories ?? 0 }
}
