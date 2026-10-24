import SwiftUI

/// Full meal history grouped by day, with swipe-to-delete.
struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    private var grouped: [(day: Date, meals: [Meal])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: model.meals) { cal.startOfDay(for: $0.timestamp) }
        return dict.keys.sorted(by: >).map { key in
            (key, dict[key]!.sorted { $0.timestamp > $1.timestamp })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("History")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 8)

                if model.meals.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.day) { group in
                        daySection(group.day, group.meals)
                    }
                }

                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .nutriBackground()
    }

    private func daySection(_ day: Date, _ meals: [Meal]) -> some View {
        let total = meals.reduce(0.0) { $0 + $1.totals.calories }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayLabel(day))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(total)) kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(meals) { meal in
                MealRow(meal: meal)
                    .contextMenu {
                        Button(role: .destructive) { model.deleteMeal(meal) } label: {
                            Label("Delete meal", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No meals logged yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Scan a meal to start building your history.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
