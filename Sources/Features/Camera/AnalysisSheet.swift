import SwiftUI

/// Elegant food-analysis bottom sheet. Lets the user review, edit, and confirm
/// the recognized meal, see a coaching tip, run an eating timer, and optionally
/// estimate how much was consumed via a before/after plate photo.
struct AnalysisSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var capturedImage: UIImage?
    /// Called when the user wants to scan another item into this meal; the
    /// presenter closes the sheet so the camera is ready for another capture.
    var onScanMore: (() -> Void)? = nil

    @State private var editingItem: FoodItem?
    @State private var showTimer = false
    @State private var showAfterPicker = false
    @State private var consumedFraction: Double?
    @State private var consumptionNote: String?
    @State private var estimatingConsumption = false

    private var meal: Meal? { model.pendingMeal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let warning = model.avoidWarning(for: meal?.items ?? []) {
                    avoidWarningBanner(warning)
                }

                if let note = model.recognitionNote {
                    aiNoteBanner(note)
                }

                if let tip = model.pendingCoachTip {
                    coachTipCard(tip)
                } else if model.aiConfigured {
                    coachLoadingCard
                }

                totalsCard

                itemsSection

                behaviorSection

                actionButtons
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $editingItem) { item in
            EditFoodItemView(item: item) { updated in
                model.updatePendingItem(updated)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAfterPicker) {
            PhotoPicker { after in
                Task { await estimateConsumption(after: after) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meal?.mealType ?? "Meal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.calories)
            Text("Here's what I see")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func avoidWarningBanner(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) {
                Text("STOP")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black)
                Text(warning)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.warning))
    }

    private func aiNoteBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: model.aiConfigured ? "checkmark.seal.fill" : "info.circle.fill")
                .foregroundStyle(model.aiConfigured ? Theme.positive : Theme.warning)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
    }

    private func coachTipCard(_ tip: String) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.protein)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.protein)
                    Text(tip)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var coachLoadingCard: some View {
        Card {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.protein)
                Text("Coach is thinking…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var totalsCard: some View {
        Card {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(meal?.totals.calories ?? 0))")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("total calories")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let fraction = consumedFraction {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(fraction * 100))%")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.carbs)
                            Text("eaten (est.)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    MacroChip(kind: .protein, value: meal?.totals.proteinG ?? 0)
                    MacroChip(kind: .carbs, value: meal?.totals.carbsG ?? 0)
                    MacroChip(kind: .fat, value: meal?.totals.fatG ?? 0)
                    Spacer()
                }
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected foods")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(meal?.items ?? []) { item in
                foodRow(item)
            }
        }
    }

    private func foodRow(_ item: FoodItem) -> some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ConfidenceBadge(confidence: item.confidence)
                    }
                    Text(item.portionDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        MacroChip(kind: .calories, value: item.macros.calories)
                        MacroChip(kind: .protein, value: item.macros.proteinG)
                    }
                }
                Spacer()
                VStack(spacing: 10) {
                    Button { editingItem = item } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.cardElevated))
                    }
                    Button { model.removePendingItem(item) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.cardElevated))
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("While you eat")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            if let onScanMore {
                Button { onScanMore() } label: {
                    behaviorRow(icon: "plus.viewfinder", title: "Scan another item",
                                subtitle: "Add more food to this meal")
                }
            }

            Button { showTimer = true } label: {
                behaviorRow(icon: "timer", title: "Start eating timer",
                            subtitle: "Pace awareness + slow-down nudges")
            }
            .sheet(isPresented: $showTimer) {
                MealTimerView(meal: meal)
                    .environmentObject(model)
                    .presentationDetents([.large])
            }

            Button { showAfterPicker = true } label: {
                behaviorRow(icon: "photo.stack",
                            title: estimatingConsumption ? "Estimating…" : "Estimate amount eaten",
                            subtitle: "Snap the plate after eating (stretch, approximate)")
            }
            .disabled(estimatingConsumption)

            if let note = consumptionNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func behaviorRow(icon: String, title: String, subtitle: String) -> some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.carbs)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                model.confirmPendingMeal(consumedFraction: consumedFraction)
                dismiss()
            } label: {
                Text("Log this meal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [Theme.calories, Theme.protein],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button {
                model.discardPendingMeal()
                dismiss()
            } label: {
                Text("Discard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Consumption estimate (stretch)

    private func estimateConsumption(after: UIImage) async {
        guard let before = capturedImage else {
            consumptionNote = "Need the original plate photo to compare."
            return
        }
        estimatingConsumption = true
        defer { estimatingConsumption = false }

        let result = await ConsumptionEstimator.estimate(before: before, after: after)
        consumedFraction = result.fraction
        consumptionNote = result.note
    }
}

/// Edit a single food item's values.
struct EditFoodItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: FoodItem
    var onSave: (FoodItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $item.name)
                    TextField("Portion", text: $item.portionDescription)
                }
                Section("Nutrition") {
                    stepperRow("Calories", value: $item.macros.calories, step: 10)
                    stepperRow("Protein (g)", value: $item.macros.proteinG, step: 1)
                    stepperRow("Carbs (g)", value: $item.macros.carbsG, step: 1)
                    stepperRow("Fat (g)", value: $item.macros.fatG, step: 1)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(item); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stepperRow(_ label: String, value: Binding<Double>, step: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value.wrappedValue))").foregroundStyle(Theme.textSecondary)
            Stepper("", value: value, in: 0...5000, step: step).labelsHidden()
        }
    }
}
