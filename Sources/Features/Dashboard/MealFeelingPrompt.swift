import SwiftUI

/// Quick post-meal check-in: "How do you feel?" Tapping a feeling records it on
/// the meal; a negative rating adds its foods to the avoid list.
struct MealFeelingPrompt: View {
    @EnvironmentObject var model: AppModel
    let meal: Meal
    var onDone: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How do you feel?")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("After \(meal.title.lowercased())")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { onDone() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.cardElevated))
                    }
                }

                HStack(spacing: 8) {
                    ForEach(MealFeeling.allCases) { feeling in
                        Button {
                            model.rateMeal(meal, feeling: feeling)
                            onDone()
                        } label: {
                            VStack(spacing: 5) {
                                Text(feeling.emoji).font(.system(size: 26))
                                Text(feeling.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                        }
                    }
                }

                Text("If it didn't sit well, I'll add it to your avoid list and warn you next time the camera sees it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
