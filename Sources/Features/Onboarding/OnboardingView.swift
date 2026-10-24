import SwiftUI

/// Interactive, multi-step onboarding. Collects the inputs a TDEE calculator
/// needs, computes calorie + macro targets live, and lets the user fine-tune.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = UserProfile.default
    @State private var step = 0

    private let totalSteps = 6  // welcome, basics, body, activity, goal, targets

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ZStack {
                switch step {
                case 0: welcomeStep
                case 1: basicsStep
                case 2: bodyStep
                case 3: activityStep
                case 4: goalStep
                default: targetsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(step)
            .animation(.easeInOut(duration: 0.3), value: step)

            footer
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .background(
                    Theme.background.opacity(0.95)
                        .ignoresSafeArea(edges: .bottom)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: -4)
                )
        }
        .nutriBackground()
    }

    // MARK: - Chrome

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.accentGradient : LinearGradient(colors: [Theme.cardElevated, Theme.cardElevated], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 5)
                    .animation(.easeInOut, value: step)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { withAnimation { step -= 1 } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                }
            }
            Button {
                if step == totalSteps - 1 { finish() }
                else { withAnimation { advance() } }
            } label: {
                Text(step == totalSteps - 1 ? "Start eating smarter" : "Continue")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.calories.opacity(0.4), radius: 14, y: 6)
            }
        }
    }

    private func advance() {
        // Recompute targets when leaving the goal step.
        if step == 4 { draft.recomputeTargetsIfNeeded(force: true); draft.targetsManuallyEdited = false }
        step += 1
    }

    private func finish() {
        var profile = draft
        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty { profile.name = "there" }
        profile.hasCompletedOnboarding = true
        model.profile = profile
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 72, height: 72)
                    .shadow(color: Theme.calories.opacity(0.5), radius: 18, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .bold)).foregroundStyle(.black)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Meet NutriWear")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your AI eating coach. It sees your plate, understands your goals, and guides you while you eat — not just after.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                featureRow("camera.viewfinder", "Scan meals", "Instant food + macro recognition")
                featureRow("waveform", "Ask out loud", "A voice coach while you eat")
                featureRow("chart.pie.fill", "Smart targets", "Calories tuned to your body")
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func featureRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.calories)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.card))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(sub).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var basicsStep: some View {
        StepScaffold(title: "The basics", subtitle: "So your coach knows who it's talking to.") {
            VStack(spacing: 18) {
                FieldLabel("What should I call you?")
                TextField("", text: $draft.name, prompt: Text("Your name").foregroundColor(Theme.textTertiary))
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke, lineWidth: 1))

                FieldLabel("Biological sex")
                    .padding(.top, 4)
                SegmentPicker(options: BiologicalSex.allCases.map { $0.rawValue },
                              selection: draft.sex.rawValue) { picked in
                    if let s = BiologicalSex(rawValue: picked) { draft.sex = s }
                }

                FieldLabel("Age").padding(.top, 4)
                StepperField(value: $draft.age, range: 13...100, unit: "years")
            }
        }
    }

    private var bodyStep: some View {
        StepScaffold(title: "Your body", subtitle: "Used to estimate your energy needs.") {
            VStack(spacing: 22) {
                ValueSlider(title: "Height", value: $draft.heightCm, range: 130...220, step: 1,
                            format: { "\(Int($0)) cm" })
                ValueSlider(title: "Weight", value: $draft.weightKg, range: 35...180, step: 0.5,
                            format: { String(format: "%.1f kg", $0) })
            }
        }
    }

    private var activityStep: some View {
        StepScaffold(title: "How active are you?", subtitle: "Pick what matches a typical week.") {
            VStack(spacing: 10) {
                ForEach(ActivityLevel.allCases) { level in
                    SelectableRow(
                        title: level.rawValue,
                        subtitle: level.detail,
                        selected: draft.activity == level
                    ) { draft.activity = level }
                }
            }
        }
    }

    private var goalStep: some View {
        StepScaffold(title: "Your main goal", subtitle: "This shapes your calorie target and coaching.") {
            VStack(spacing: 10) {
                ForEach(PrimaryGoal.allCases) { goal in
                    SelectableRow(
                        title: goal.rawValue,
                        subtitle: goal.detail,
                        icon: goal.icon,
                        selected: draft.goal == goal
                    ) { draft.goal = goal }
                }
                FieldLabel("Dietary preference").padding(.top, 10)
                Menu {
                    ForEach(DietPreference.allCases) { diet in
                        Button(diet.rawValue) { draft.diet = diet }
                    }
                } label: {
                    HStack {
                        Text(draft.diet.rawValue).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.textTertiary)
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke, lineWidth: 1))
                }
            }
        }
    }

    private var targetsStep: some View {
        TargetsReviewView(draft: $draft)
    }
}

// MARK: - Final step: computed targets with manual override

private struct TargetsReviewView: View {
    @Binding var draft: UserProfile

    private var computed: TDEECalculator.Output { TDEECalculator.compute(draft.tdeeInputs) }

    var body: some View {
        StepScaffold(title: "Your plan", subtitle: "Calculated from your body and goal. Adjust anything you like.") {
            VStack(spacing: 18) {
                // Hero calorie number
                Card {
                    VStack(spacing: 10) {
                        Text("DAILY CALORIE TARGET")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .tracking(1.2)
                        Text("\(Int(draft.dailyCalorieTarget))")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("kcal / day")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)

                        HStack(spacing: 18) {
                            miniStat("BMR", Int(computed.bmr))
                            Divider().frame(height: 26).overlay(Theme.stroke)
                            miniStat("TDEE", Int(computed.tdee))
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Calorie fine-tune
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        FieldLabel("Fine-tune calories")
                        Spacer()
                        if draft.targetsManuallyEdited {
                            Button("Reset to calculated") {
                                draft.recomputeTargetsIfNeeded(force: true)
                                draft.targetsManuallyEdited = false
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.calories)
                        }
                    }
                    Slider(value: Binding(
                        get: { draft.dailyCalorieTarget },
                        set: { newValue in
                            draft.dailyCalorieTarget = newValue.rounded()
                            draft.targetsManuallyEdited = true
                            // Re-split macros to match the new calorie goal.
                            let m = TDEECalculator.macros(for: newValue.rounded(), goal: draft.goal, weightKg: draft.weightKg)
                            draft.dailyProteinTarget = m.proteinG
                            draft.dailyCarbTarget = m.carbsG
                            draft.dailyFatTarget = m.fatG
                        }
                    ), in: 1200...4000, step: 25)
                    .tint(Theme.calories)
                }

                // Macro breakdown
                Card {
                    VStack(spacing: 14) {
                        macroAdjustRow(.protein, $draft.dailyProteinTarget, 0...300)
                        macroAdjustRow(.carbs, $draft.dailyCarbTarget, 0...500)
                        macroAdjustRow(.fat, $draft.dailyFatTarget, 0...200)
                    }
                }
            }
        }
    }

    private func miniStat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func macroAdjustRow(_ kind: MacroKind, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color.macro(kind)).frame(width: 9, height: 9)
                Text(kind.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue)) g").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.macro(kind))
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0.rounded(); draft.targetsManuallyEdited = true }
            ), in: range, step: 1)
            .tint(Color.macro(kind))
        }
    }
}

// MARK: - Reusable step building blocks

private struct StepScaffold<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            // Clear the floating footer button (~100pt).
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        // Top-anchor content so short pages don't float to the center.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SegmentPicker: View {
    let options: [String]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    Text(option)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(option == selection ? .black : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(option == selection ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: option == selection ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack {
            Button { if value > range.lowerBound { value -= 1 } } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.card)).foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                Text(unit).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { if value < range.upperBound { value += 1 } } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.card)).foregroundStyle(Theme.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(format(value))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.calories)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: range, step: step).tint(Theme.calories)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: 1))
    }
}

private struct SelectableRow: View {
    let title: String
    let subtitle: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? .black : Theme.calories)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(selected ? AnyShapeStyle(Color.white.opacity(0.25)) : AnyShapeStyle(Theme.cardElevated)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? .black : Theme.textPrimary)
                    Text(subtitle).font(.system(size: 12))
                        .foregroundStyle(selected ? .black.opacity(0.7) : Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? .black : Theme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.card))
            )
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}
