import SwiftUI

/// The AI eating coach + voice assistant. Users can tap quick questions, type,
/// or speak. Answers are shown and optionally spoken aloud.
struct CoachView: View {
    @EnvironmentObject var model: AppModel
    /// Use the app-wide speech service so voice commands drive eating sessions
    /// and spoken cues share one engine. Injected so the view observes it.
    @ObservedObject var speech: SpeechService

    @State private var messages: [CoachMessage] = []
    @State private var inputText = ""
    @State private var thinking = false
    @State private var speakReplies = true

    private let quickQuestions = [
        "What should I eat first?",
        "How much protein do I have left today?",
        "Am I eating too fast?",
        "Does my last meal fit my goals?"
    ]

    /// The most recent meal provides context for the coach.
    private var contextMeal: Meal? {
        model.pendingMeal ?? model.meals(on: Date()).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            intro
                        }
                        ForEach(messages) { message in
                            CoachBubble(message: message)
                                .id(message.id)
                        }
                        if thinking {
                            CoachBubble(message: CoachMessage(role: .coach, text: "…", pending: true))
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if model.isEating {
                activeSessionBanner
            }
            if let err = speech.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
            }
            quickQuestionRow
            inputBar
            Color.clear.frame(height: 96)
        }
        .nutriBackground()
        .onChange(of: speech.transcript) { _, newValue in
            inputText = newValue
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.aiConfigured ? "Live · Groq" : "Offline mode")
                    .font(.system(size: 12))
                    .foregroundStyle(model.aiConfigured ? Theme.positive : Theme.warning)
            }
            Spacer()
            Button { speakReplies.toggle() } label: {
                Image(systemName: speakReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(speakReplies ? Theme.calories : Theme.textTertiary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.card))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Theme.protein)
            Text("Ask me anything while you eat")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("I know your goals and what you've eaten today. Tap a question, type, or hit the mic to ask out loud.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 20)
    }

    private var quickQuestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickQuestions, id: \.self) { q in
                    Button { send(q) } label: {
                        Text(q)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.card))
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8)
    }

    /// Shows the live eating session with a hands-free listen control.
    private var activeSessionBanner: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.calories).frame(width: 8, height: 8)
            Text("Eating · \(durationString(model.activeSession?.elapsedSeconds ?? 0))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Spacer()
            Button {
                Task {
                    if speech.isListening { speech.stopListening() }
                    else {
                        if !speech.authorized { await speech.requestAuthorization() }
                        if speech.authorized { speech.startListening(command: true) }
                    }
                }
            } label: {
                Text(speech.isListening ? "Listening…" : "Hands-free")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(speech.isListening ? .black : Theme.calories)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(speech.isListening ? Theme.calories : Theme.card))
            }
            Button { model.finishEatingSession() } label: {
                Text("I'm done")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.cardElevated))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func durationString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Mic button — requests permission lazily on first tap.
            Button {
                if speech.isListening {
                    speech.stopListening()
                    if !inputText.isEmpty { send(inputText) }
                } else {
                    Task {
                        if !speech.authorized { await speech.requestAuthorization() }
                        if speech.authorized { speech.startListening() }
                    }
                }
            } label: {
                Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(speech.isListening ? .black : Theme.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(speech.isListening ? Theme.calories : Theme.card))
            }

            HStack {
                TextField("Ask your coach…", text: $inputText)
                    .foregroundStyle(Theme.textPrimary)
                    .submitLabel(.send)
                    .onSubmit { send(inputText) }
                if !inputText.isEmpty {
                    Button { send(inputText) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.calories)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Send

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thinking else { return }
        if speech.isListening { speech.stopListening() }

        // Session commands ("let's eat", "I'm done") act directly rather than
        // becoming a coach question.
        if VoiceCommandRouter.isSessionCommand(question) {
            _ = model.handleVoiceTranscript(question)
            inputText = ""
            speech.transcript = ""
            let ack = model.isEating ? "Started your meal — I'm watching your pace." : "Okay, logged. Nice work."
            messages.append(CoachMessage(role: .user, text: question))
            messages.append(CoachMessage(role: .coach, text: ack))
            return
        }

        messages.append(CoachMessage(role: .user, text: question))
        inputText = ""
        speech.transcript = ""
        thinking = true

        let duration = model.activeSession?.elapsedSeconds ?? contextMeal?.durationSeconds
        Task {
            let answer = await model.askCoach(question, currentMeal: contextMeal, eatingDurationSeconds: duration)
            await MainActor.run {
                thinking = false
                messages.append(CoachMessage(role: .coach, text: answer))
                if speakReplies { speech.speak(answer) }
            }
        }
    }
}

struct CoachMessage: Identifiable {
    enum Role { case user, coach }
    let id = UUID()
    let role: Role
    let text: String
    var pending: Bool = false
}

struct CoachBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Group {
                if message.pending {
                    ProgressView().tint(Theme.protein).padding(.horizontal, 6)
                } else {
                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(message.role == .user ? .black : Theme.textPrimary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(message.role == .user ? Theme.calories : Theme.card)
            )
            if message.role == .coach { Spacer(minLength: 40) }
        }
    }
}
