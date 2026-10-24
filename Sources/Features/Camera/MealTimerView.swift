import SwiftUI

/// Live meal timer with eating-pace awareness and optional slow-down nudges.
/// We track elapsed time only — we do NOT pretend to detect chewing or bites.
struct MealTimerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var meal: Meal?

    @State private var elapsed = 0
    @State private var running = true
    @State private var lastNudge = 0
    @State private var paceMessage = "Nice and steady. Try putting your fork down between bites."

    // A gentle "slow down" threshold: if a sizeable meal is going very fast.
    private var mealCalories: Double { meal?.totals.calories ?? 0 }

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

            if model.profile.slowEatingReminders {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.protein)
                        Text(paceMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            HStack(spacing: 12) {
                Button { running.toggle() } label: {
                    Label(running ? "Pause" : "Resume", systemImage: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                }
                Button {
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
        .task {
            // Main-actor tick loop; avoids Combine Timer Sendable issues under Swift 6.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard running else { continue }
                elapsed += 1
                updatePace()
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

    private func updatePace() {
        // Nudge roughly every 4 minutes if going fast on a larger meal.
        if model.profile.slowEatingReminders,
           elapsed - lastNudge >= 240,
           elapsed < 10 * 60, mealCalories > 400 {
            lastNudge = elapsed
            paceMessage = "You're moving quickly. Slowing down helps your body register fullness. Try a sip of water between bites."
        } else if elapsed == 20 * 60 {
            paceMessage = "20 minutes in — that's a well-paced meal. Your fullness signals have had time to catch up."
        }
    }
}
