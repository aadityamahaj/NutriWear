import Foundation
import SwiftUI
import Combine

/// App-wide source of truth. Owns meals, profile, daily totals, and bridges to
/// the AI services. Views observe this.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile {
        didSet { PersistenceStore.saveProfile(profile); pushToCloud() }
    }
    @Published var meals: [Meal] {
        didSet { PersistenceStore.saveMeals(meals); pushToCloud() }
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

    // MARK: - Proactive eating session

    /// Shared speech service so voice commands and spoken cues use one engine.
    let speech = SpeechService()
    let notifications = NotificationService()
    /// Bluetooth connectivity for current and future NutriWear hardware.
    let bluetooth = BluetoothService()

    // MARK: - Account / auth

    let auth = AuthService()
    /// Guest vs signed-in vs not-yet-chosen. Drives the welcome gate.
    @Published var accountMode: AccountMode = .unchosen
    private let accountModeKey = "nutriwear.account.mode.v1"
    /// Backend sync for a signed-in user's profile + meals.
    private lazy var userSync = UserSyncClient(auth: auth)

    var authConfigured: Bool { auth.isConfigured }

    /// The in-progress eating session (nil when not eating). Drives the
    /// proactive coach and hands-free voice commands.
    @Published var activeSession: ActiveEatingSession?
    /// The latest proactive cue, surfaced in the UI as a banner.
    @Published var lastCueMessage: String?

    /// AI-generated eating-habit suggestions (Insights screen).
    @Published var improvementSuggestions: [String] = []
    @Published var loadingSuggestions = false

    /// Computed analytics over all logged meals.
    var insights: EatingInsights { EatingInsights(meals: meals) }

    /// Regenerate personalized improvement suggestions from logged history.
    func refreshSuggestions() async {
        loadingSuggestions = true
        let facts = insights.factSheet
        let result = await coach.improvementSuggestions(profile: profile, facts: facts)
        improvementSuggestions = result
        loadingSuggestions = false
    }

    private var sessionTask: Task<Void, Never>?
    private var firedCues: Set<CoachCue> = []

    var isEating: Bool { activeSession != nil }

    var aiConfigured: Bool { GroqClient.isConfigured }

    init() {
        self.profile = PersistenceStore.loadProfile()
        self.meals = PersistenceStore.loadMeals()

        // Restore account choice. If a signed-in session exists, honor it;
        // otherwise fall back to the saved guest/unchosen mode.
        if let raw = UserDefaults.standard.string(forKey: accountModeKey),
           let mode = AccountMode(rawValue: raw) {
            self.accountMode = mode
        }
        if auth.isSignedIn { self.accountMode = .signedIn }

        // When the wearable ends a session, log it as a meal automatically.
        sync.onSessionEnded = { [weak self] session in
            self?.logSyncedSession(session)
        }

        // Route hands-free voice (command mode only): session commands act
        // directly; a non-command utterance becomes a coach question answered
        // aloud. The Coach screen's push-to-talk mic handles its own sends, so
        // we only auto-answer here when listening hands-free during a meal.
        speech.onFinalTranscript = { [weak self] transcript in
            guard let self, self.speech.commandMode else { return }
            if let question = self.handleVoiceTranscript(transcript) {
                guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task {
                    let meal = self.activeSession?.meal ?? self.pendingMeal ?? self.meals(on: Date()).first
                    let answer = await self.askCoach(question, currentMeal: meal,
                                                     eatingDurationSeconds: self.activeSession?.elapsedSeconds)
                    await MainActor.run {
                        self.lastCueMessage = answer
                        if self.profile.coaching.channel.usesVoice { self.speech.speak(answer) }
                    }
                }
            }
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

    // MARK: - Proactive eating session engine

    /// Begin a live eating session. `meal` is the scanned plate if available.
    /// Starts the proactive coach loop and (optionally) hands-free listening.
    func startEatingSession(meal: Meal? = nil, startedBy: ActiveEatingSession.StartSource = .manual) {
        guard activeSession == nil else { return }
        let session = ActiveEatingSession(startedAt: Date(), meal: meal, startedBy: startedBy)
        activeSession = session
        firedCues = []
        lastCueMessage = nil

        // Ask for notification permission up front if that channel is used.
        if profile.coaching.channel.usesNotification {
            Task { await notifications.requestAuthorizationIfNeeded() }
        }

        // Start-of-meal confirmation cue.
        fireCue(.startReminder)

        // Begin the pace-watching loop.
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in await self?.runSessionLoop() }
    }

    func pauseEatingSession() {
        activeSession?.paused = true
    }

    func resumeEatingSession() {
        activeSession?.paused = false
    }

    /// End the session. Logs the meal (if any) with its eating duration and
    /// delivers the finish summary cue.
    func finishEatingSession() {
        guard let session = activeSession else { return }
        sessionTask?.cancel()
        sessionTask = nil

        // Deliver the wrap-up before we tear down state.
        fireCue(.finishSummary)

        if let meal = session.meal {
            if pendingMeal?.id == meal.id {
                // Still pending → log it now, carrying the eating duration.
                confirmPendingMeal(durationSeconds: session.elapsedSeconds)
            } else if let idx = meals.firstIndex(where: { $0.id == meal.id }) {
                // Already logged (e.g. voice-started on an existing meal) →
                // just attach the measured duration.
                meals[idx].durationSeconds = session.elapsedSeconds
            } else {
                var logged = meal
                logged.durationSeconds = session.elapsedSeconds
                meals.append(logged)
            }
        }

        activeSession = nil
        firedCues = []
        // Stop hands-free listening if it was on for this session.
        if speech.commandMode { speech.stopListening() }
    }

    /// The pace-watching loop. Ticks each second, advancing elapsed time and
    /// evaluating whether a proactive cue should fire.
    private func runSessionLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard var session = activeSession else { break }
            guard !session.paused else { continue }
            session.elapsedSeconds += 1
            activeSession = session
            evaluateCues(for: session)
        }
    }

    /// Decide which cue (if any) to fire at the current elapsed time.
    private func evaluateCues(for session: ActiveEatingSession) {
        let prefs = profile.coaching
        guard prefs.isActive else { return }
        let pace = paceSnapshot(for: session)

        // Slow-down: fire once when a big meal is going too fast (after ~90s).
        if !firedCues.contains(.slowDown),
           session.elapsedSeconds >= 90,
           pace.isTooFast {
            fireCue(.slowDown, pace: pace)
        }

        // Halfway check-in around the 8-minute mark on a normal-length meal.
        if !firedCues.contains(.halfwayCheck),
           session.elapsedSeconds == 8 * 60 {
            fireCue(.halfwayCheck, pace: pace)
        }

        // Hydration nudge at ~4 minutes if opted in.
        if !firedCues.contains(.hydration),
           session.elapsedSeconds == 4 * 60 {
            fireCue(.hydration, pace: pace)
        }
    }

    private func paceSnapshot(for session: ActiveEatingSession) -> CoachService.PaceSnapshot {
        CoachService.PaceSnapshot(
            elapsedSeconds: session.elapsedSeconds,
            mealCalories: session.mealCalories,
            consumedFraction: session.meal?.consumedFraction
        )
    }

    /// Fire a proactive cue if preferences allow it, generating a personalized
    /// line and delivering it via the chosen channel(s).
    private func fireCue(_ cue: CoachCue, pace: CoachService.PaceSnapshot? = nil) {
        let prefs = profile.coaching
        guard prefs.shouldFire(cue) else { return }
        firedCues.insert(cue)

        let snapshot = pace ?? (activeSession.map { paceSnapshot(for: $0) }
                                ?? CoachService.PaceSnapshot(elapsedSeconds: 0, mealCalories: 0, consumedFraction: nil))
        let ctx = coachContext(currentMeal: activeSession?.meal,
                               eatingDurationSeconds: activeSession?.elapsedSeconds)
        Task { [weak self] in
            guard let self else { return }
            let message = await self.coach.cueMessage(for: cue, context: ctx, pace: snapshot)
            await MainActor.run { self.deliverCue(message, cue: cue) }
        }
    }

    private func deliverCue(_ message: String, cue: CoachCue) {
        lastCueMessage = message
        let channel = profile.coaching.channel
        if channel.usesVoice {
            speech.speak(message)
        }
        if channel.usesNotification {
            notifications.notify(title: "NutriWear Coach", body: message, identifier: cue.rawValue)
        }
    }

    // MARK: - Voice command handling

    /// Route a final spoken transcript to the right action. Returns the coach
    /// question text when the utterance was NOT a session command (so the
    /// caller can display/answer it); nil when a command was handled.
    func handleVoiceTranscript(_ transcript: String) -> String? {
        switch VoiceCommandRouter.classify(transcript) {
        case .startEating:
            if activeSession == nil {
                startEatingSession(meal: pendingMeal ?? meals(on: Date()).first, startedBy: .voice)
            }
            return nil
        case .doneEating:
            if activeSession != nil { finishEatingSession() }
            return nil
        case .pause:
            pauseEatingSession(); return nil
        case .resume:
            resumeEatingSession(); return nil
        case .askCoach(let q):
            return q
        }
    }

    // MARK: - Account

    func chooseGuest() {
        accountMode = .guest
        UserDefaults.standard.set(AccountMode.guest.rawValue, forKey: accountModeKey)
    }

    /// Called after a successful OTP verification.
    func didSignIn() {
        accountMode = .signedIn
        UserDefaults.standard.set(AccountMode.signedIn.rawValue, forKey: accountModeKey)
        // Pull the user's cloud data, then keep it in sync.
        Task { await syncFromCloud() }
    }

    func signOut() {
        auth.signOut()
        accountMode = .unchosen
        UserDefaults.standard.removeObject(forKey: accountModeKey)
    }

    /// Load the signed-in user's profile + meals from the backend, if newer.
    func syncFromCloud() async {
        guard accountMode == .signedIn, auth.isSignedIn else { return }
        if let remote = await userSync.fetch() {
            if let p = remote.profile { profile = p }
            if let m = remote.meals, !m.isEmpty { meals = m }
        }
    }

    /// Push current profile + meals to the backend for a signed-in user.
    func pushToCloud() {
        guard accountMode == .signedIn, auth.isSignedIn else { return }
        Task { await userSync.push(profile: profile, meals: meals) }
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
