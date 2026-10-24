import Foundation

/// How the user felt after a meal. Captured via a quick post-meal rating and
/// used to learn which foods to flag as "avoid".
enum MealFeeling: String, Codable, CaseIterable, Identifiable {
    case great
    case good
    case okay
    case sluggish
    case bad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .okay: return "Okay"
        case .sluggish: return "Sluggish"
        case .bad: return "Bad"
        }
    }

    var emoji: String {
        switch self {
        case .great: return "😀"
        case .good: return "🙂"
        case .okay: return "😐"
        case .sluggish: return "😮‍💨"
        case .bad: return "🤢"
        }
    }

    /// Lower is worse. Used to decide which foods correlate with feeling bad.
    var score: Int {
        switch self {
        case .great: return 5
        case .good: return 4
        case .okay: return 3
        case .sluggish: return 2
        case .bad: return 1
        }
    }

    /// Feelings that count as "didn't sit well".
    var isNegative: Bool { score <= 2 }
}
