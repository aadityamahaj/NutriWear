import Foundation

/// Interprets a spoken transcript into a high-level intent. Keeps the keyword
/// matching in one place so both the Coach screen and the eating-session flow
/// can share it. Pure and synchronous — trivially testable.
enum VoiceCommand: Equatable {
    case startEating            // "let's eat", "start eating", "I'm eating now"
    case doneEating             // "I'm done", "finished", "all done"
    case pause                  // "pause", "hold on"
    case resume                 // "resume", "keep going"
    case askCoach(String)       // anything else → a coach question
}

enum VoiceCommandRouter {

    /// Phrases that start an eating session.
    private static let startPatterns = [
        #"\blet'?s eat\b"#,
        #"\bstart (eating|the meal|my meal|a meal|the timer)\b"#,
        #"\bi'?m (eating|about to eat|gonna eat|going to eat)\b"#,
        #"\bbegin (eating|the meal)\b"#,
        #"\btime to eat\b"#
    ]

    /// Phrases that end logging.
    private static let donePatterns = [
        #"\bi'?m (done|finished|full)\b"#,
        #"\b(all done|that'?s it|that is it|i am done|i am finished)\b"#,
        #"\b(stop|end|finish) (eating|the meal|logging|the timer)\b"#,
        #"\bfinished eating\b"#,
        #"^\s*(done|finished)\s*$"#
    ]

    private static let pausePatterns = [#"\bpause\b"#, #"\bhold on\b"#, #"\bone (second|sec|moment)\b"#]
    private static let resumePatterns = [#"\bresume\b"#, #"\bkeep going\b"#, #"\bcontinue\b"#, #"\bun ?pause\b"#]

    /// Classify a transcript. Returns `.askCoach` when nothing matches a command.
    static func classify(_ transcript: String) -> VoiceCommand {
        let t = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .askCoach("") }

        if matchesAny(t, donePatterns)  { return .doneEating }
        if matchesAny(t, startPatterns) { return .startEating }
        if matchesAny(t, pausePatterns) { return .pause }
        if matchesAny(t, resumePatterns){ return .resume }
        return .askCoach(transcript)
    }

    /// True when the transcript contains a start/stop command (used to decide
    /// whether a final utterance should trigger an action vs. a coach question).
    static func isSessionCommand(_ transcript: String) -> Bool {
        switch classify(transcript) {
        case .startEating, .doneEating, .pause, .resume: return true
        case .askCoach: return false
        }
    }

    private static func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        for p in patterns {
            if text.range(of: p, options: [.regularExpression]) != nil { return true }
        }
        return false
    }
}
