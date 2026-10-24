import SwiftUI

/// Big circular calorie ring with remaining count in the middle (NutriAI style).
struct CalorieRing: View {
    var consumed: Double
    var target: Double

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, consumed / target)
    }
    private var remaining: Double { max(0, target - consumed) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardElevated, lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Theme.calories, Theme.protein, Theme.calories],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)

            VStack(spacing: 2) {
                Text("\(Int(remaining))")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("kcal left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(Int(consumed)) of \(Int(target))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
    }
}

/// Horizontal macro progress bar with label and values.
struct MacroBar: View {
    var kind: MacroKind
    var consumed: Double
    var target: Double

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, consumed / target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(consumed)) / \(Int(target)) \(kind.unit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardElevated)
                    Capsule()
                        .fill(Color.macro(kind))
                        .frame(width: max(6, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

/// Small pill showing a macro value (used on food cards).
struct MacroChip: View {
    var kind: MacroKind
    var value: Double

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.macro(kind)).frame(width: 6, height: 6)
            Text("\(Int(value))\(kind == .calories ? "" : "g")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(kind == .calories ? "kcal" : kind.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.cardElevated))
    }
}

/// Confidence badge for uncertain estimates.
struct ConfidenceBadge: View {
    var confidence: Confidence

    private var color: Color {
        switch confidence {
        case .high: return Theme.positive
        case .medium: return Theme.warning
        case .low: return Theme.textTertiary
        }
    }

    var body: some View {
        Text(confidence.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
