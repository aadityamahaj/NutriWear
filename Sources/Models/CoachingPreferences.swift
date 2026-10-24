import Foundation

/// How proactive coaching cues reach the user while they eat.
enum CoachDeliveryChannel: String, Codable, CaseIterable, Identifiable {
    case voice          // spoken aloud via TTS
    case notification   // local notification banner + haptic
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .voice: return "Spoken (voice)"
        case .notification: return "Notifications"
        case .both: return "Voice + notifications"
        }
    }

    var icon: String {
        switch self {
        case .voice: return "speaker.wave.2.fill"
        case .notification: return "bell.badge.fill"
        case .both: return "bell.and.waveform.fill"
        }
    }

    var usesVoice: Bool { self == .voice || self == .both }
    var usesNotification: Bool { self == .notification || self == .both }
}

/// Individual proactive cues the user can opt into. When auto-coaching is off,
/// only the cues enabled here will fire; when it's on, all of these are active.
enum CoachCue: String, Codable, CaseIterable, Identifiable {
    case slowDown        // eating a sizeable meal too fast
    case halfwayCheck    // gentle midpoint check-in on pace/fullness
    case startReminder   // confirmation the coach is watching when a meal starts
    case finishSummary   // short spoken/notified summary when a meal ends
    case hydration       // nudge to sip water between bites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slowDown: return "Slow-down nudges"
        case .halfwayCheck: return "Halfway check-in"
        case .startReminder: return "Meal start confirmation"
        case .finishSummary: return "Finish summary"
        case .hydration: return "Hydration reminders"
        }
    }

    var detail: String {
        switch self {
        case .slowDown: return "Tells you to ease up if a big meal is disappearing fast"
        case .halfwayCheck: return "Checks in around the midpoint of your meal"
        case .startReminder: return "Confirms the coach is watching when you start"
        case .finishSummary: return "Wraps up with a quick, personalized takeaway"
        case .hydration: return "Suggests a sip of water between bites"
        }
    }

    var icon: String {
        switch self {
        case .slowDown: return "tortoise.fill"
        case .halfwayCheck: return "timer"
        case .startReminder: return "play.circle.fill"
        case .finishSummary: return "checkmark.seal.fill"
        case .hydration: return "drop.fill"
        }
    }
}

/// Proactive-coaching settings. Persisted as part of UserProfile.
struct CoachingPreferences: Codable, Equatable {
    /// Master switch. When true, every cue fires automatically during a meal.
    var autoCoach: Bool
    /// When autoCoach is off, these are the cues the user still wants.
    var enabledCues: Set<CoachCue>
    /// How cues are delivered.
    var channel: CoachDeliveryChannel

    static let `default` = CoachingPreferences(
        autoCoach: true,
        enabledCues: [.slowDown, .halfwayCheck, .finishSummary],
        channel: .both
    )

    /// Whether a given cue should actually fire given the current settings.
    func shouldFire(_ cue: CoachCue) -> Bool {
        autoCoach || enabledCues.contains(cue)
    }

    /// True if any coaching will happen at all (used to decide whether to run
    /// the proactive engine during a meal).
    var isActive: Bool {
        autoCoach || !enabledCues.isEmpty
    }
}
