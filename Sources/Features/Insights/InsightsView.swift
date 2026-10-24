import SwiftUI

/// Analysis & improvement hub: eating pace, habits, digestion signals, and
/// personalized AI suggestions based on the user's logged history.
struct InsightsView: View {
    @EnvironmentObject var model: AppModel

    private var insights: EatingInsights { model.insights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricsRow
                habitsSection
                suggestionsSection
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .nutriBackground()
        .task {
            if model.improvementSuggestions.isEmpty { await model.refreshSuggestions() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Insights")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("How you eat, and how to feel better")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 12)
    }

    // MARK: - Top metrics

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(
                value: insights.averageDurationMinutes.map { String(format: "%.0f", $0) } ?? "—",
                unit: "min",
                label: "Avg meal",
                icon: "timer",
                color: Theme.calories
            )
            metricCard(
                value: insights.fastMealRate.map { "\(Int($0 * 100))" } ?? "—",
                unit: "%",
                label: "Rushed meals",
                icon: "hare.fill",
                color: Theme.warning
            )
            metricCard(
                value: "\(insights.lateNightMealCount)",
                unit: "",
                label: "Late-night",
                icon: "moon.stars.fill",
                color: Theme.fat
            )
        }
    }

    private func metricCard(value: String, unit: String, label: String, icon: String, color: Color) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Habit cards

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your eating habits")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(insights.habitCards) { card in
                habitCard(card)
            }
        }
    }

    private func habitCard(_ card: EatingInsights.HabitCard) -> some View {
        let tone: Color = {
            switch card.tone {
            case .positive: return Theme.positive
            case .warning: return Theme.warning
            case .neutral: return Theme.carbs
            }
        }()
        return Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tone)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(card.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - AI suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Personalized plan")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Task { await model.refreshSuggestions() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.calories)
                }
                .disabled(model.loadingSuggestions)
            }

            Card {
                if model.loadingSuggestions {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.protein)
                        Text("Analyzing your habits…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else if model.improvementSuggestions.isEmpty {
                    Text("Log and time a few meals to get a personalized improvement plan.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.improvementSuggestions.enumerated()), id: \.offset) { _, s in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.positive)
                                Text(s)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            Text(model.aiConfigured
                 ? "Generated from your logged meals, pace, and timing."
                 : "Add a Groq key for AI-personalized suggestions. Showing general guidance.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }
}
