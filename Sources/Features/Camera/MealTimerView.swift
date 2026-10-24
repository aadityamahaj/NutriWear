import SwiftUI

/// Live meal timer with eating-pace awareness and optional slow-down nudges.
/// We track elapsed time only — we do NOT pretend to detect chewing or bites.
struct MealTimerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var meal: Meal?

    @State private var handsFree = false

    // Live session values come from the AppModel engine so duration persists
    // and the proactive coach runs consistently.
    private var elapsed: Int { model.activeSession?.elapsedSeconds ?? 0 }
    private var running: Bool { !(model.activeSession?.paused ?? false) }
    private var mealCalories: Double { meal?.totals.calories ?? model.activeSession?.mealCalories ?? 0 }

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(Theme.stroke).frame(width: 40, height: 5).padding(.top, 8)

            VStack(spacing: 6) {
                Text("Eating timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.calories)
                Text(timeString)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // Pace ring: fills toward a healthy ~20 min target.
            ZStack {
                Circle().stroke(Theme.cardElevated, lineWidth: 12)
                    .frame(width: 180, height: 180)
                Circle()
                    .trim(from: 0, to: min(1, Double(elapsed) / (20 * 60)))
                    .stroke(paceColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 180, height: 180)
                    .animation(.easeInOut, value: elapsed)
                VStack(spacing: 2) {
                    Image(systemName: paceIcon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(paceColor)
                    Text(paceLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let cue = model.lastCueMessage {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.protein)
                        Text(cue)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal)
            }

            handsFreeToggle

            Spacer()

            HStack(spacing: 12) {
                Button {
                    running ? model.pauseEatingSession() : model.resumeEatingSession()
                } label: {
                    Label(running ? "Pause" : "Resume", systemImage: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                }
                Button {
                    model.finishEatingSession()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.calories))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if model.activeSession == nil {
                model.startEatingSession(meal: meal, startedBy: .scan)
            }
        }
    }

    /// Hands-free listening toggle: "I'm done" ends the meal without tapping.
    private var handsFreeToggle: some View {
        Button {
            Task { await toggleHandsFree() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: handsFree ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(handsFree ? Theme.calories : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(handsFree ? "Listening — say \"I'm done\"" : "Hands-free voice")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Control the meal by voice")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(handsFree ? Theme.calories.opacity(0.5) : Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal)
    }

    private func toggleHandsFree() async {
        if handsFree {
            model.speech.stopListening()
            handsFree = false
        } else {
            if !model.speech.authorized { await model.speech.requestAuthorization() }
            if model.speech.authorized {
                model.speech.startListening(command: true)
                handsFree = true
            }
        }
    }

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private var paceColor: Color {
        if elapsed < 6 * 60 && mealCalories > 400 { return Theme.warning }
        if elapsed >= 15 * 60 { return Theme.positive }
        return Theme.carbs
    }

    private var paceIcon: String {
        if elapsed < 6 * 60 && mealCalories > 400 { return "hare.fill" }
        if elapsed >= 15 * 60 { return "tortoise.fill" }
        return "fork.knife"
    }

    private var paceLabel: String {
        if elapsed < 6 * 60 && mealCalories > 400 { return "A bit quick" }
        if elapsed >= 15 * 60 { return "Great pace" }
        return "Eating"
    }
}
