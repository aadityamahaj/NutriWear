import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showCamera: Bool
    @State private var showSettings = false
    @State private var dismissedFeelingMealID: UUID?

    private var totals: Macros { model.todayTotals }
    private var targets: Macros { model.profile.dailyTargets }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !model.aiConfigured {
                    keyBanner
                }

                if let meal = model.mealAwaitingFeeling, meal.id != dismissedFeelingMealID {
                    MealFeelingPrompt(meal: meal) { dismissedFeelingMealID = meal.id }
                }

                calorieCard
                macrosCard
                weeklyCard
                todayMealsSection

                Color.clear.frame(height: 110) // clearance for floating tab bar
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("NutriWear")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    private var keyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline demo mode")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add a Groq key in Secrets.xcconfig for live AI recognition and coaching.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.warning.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.warning.opacity(0.3), lineWidth: 1))
    }

    private var calorieCard: some View {
        Card {
            HStack(spacing: 20) {
                CalorieRing(consumed: totals.calories, target: targets.calories)
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 12) {
                    statRow("Eaten", Int(totals.calories), Theme.calories)
                    statRow("Target", Int(targets.calories), Theme.textSecondary)
                    statRow("Remaining", max(0, Int(targets.calories - totals.calories)), Theme.positive)
                }
                Spacer()
            }
        }
    }

    private func statRow(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            Text("\(value)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }

    private var macrosCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Macros today")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                MacroBar(kind: .protein, consumed: totals.proteinG, target: targets.proteinG)
                MacroBar(kind: .carbs, consumed: totals.carbsG, target: targets.carbsG)
                MacroBar(kind: .fat, consumed: totals.fatG, target: targets.fatG)
            }
        }
    }

    private var weeklyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("This week")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                let data = model.weeklyCalories()
                Chart {
                    ForEach(data, id: \.date) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("kcal", point.calories)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.calories, Theme.protein],
                                           startPoint: .bottom, endPoint: .top)
                        )
                        .cornerRadius(6)
                    }
                    RuleMark(y: .value("Target", targets.calories))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.textTertiary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var todayMealsSection: some View {
        let meals = model.meals(on: Date())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's meals")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(meals.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if meals.isEmpty {
                emptyMeals
            } else {
                ForEach(meals) { meal in
                    MealRow(meal: meal)
                }
            }
        }
    }

    private var emptyMeals: some View {
        Button { showCamera = true } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.calories)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan your first meal")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Point the camera at your plate to begin")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return "\(part), \(model.profile.name)"
    }
}

/// Compact meal row used on dashboard and history.
struct MealRow: View {
    @EnvironmentObject var model: AppModel
    var meal: Meal

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.cardElevated).frame(width: 44, height: 44)
                    Image(systemName: mealIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.calories)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(meal.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let feeling = meal.feeling {
                            Text(feeling.emoji).font(.system(size: 13))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(meal.totals.calories))")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    // Show "of Y" when we have a before/after starting total.
                    if let start = meal.startCalories, start > meal.totals.calories + 1 {
                        Text("of \(Int(start))").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("kcal").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let time = meal.timestamp.formatted(date: .omitted, time: .shortened)
        if let start = meal.startCalories, start > meal.totals.calories + 1 {
            let pct = Int((meal.totals.calories / start) * 100)
            return "\(meal.mealType) · ate \(pct)% · \(time)"
        }
        return "\(meal.mealType) · \(time)"
    }

    private var mealIcon: String {
        switch meal.mealType {
        case "Breakfast": return "sunrise.fill"
        case "Lunch": return "sun.max.fill"
        case "Dinner": return "moon.stars.fill"
        default: return "fork.knife"
        }
    }
}
