import SwiftUI

/// Edit profile, goals, and targets. Backs the personalization requirement.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $model.profile.name)
                    Picker("Goal", selection: $model.profile.goal) {
                        ForEach(PrimaryGoal.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Diet", selection: $model.profile.diet) {
                        ForEach(DietPreference.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Allergies / avoid", text: $model.profile.allergies)
                }

                Section("Body & activity") {
                    Picker("Sex", selection: $model.profile.sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("Age: \(model.profile.age)", value: $model.profile.age, in: 13...100)
                    HStack {
                        Text("Height"); Spacer()
                        Text("\(Int(model.profile.heightCm)) cm").foregroundStyle(Theme.textSecondary)
                        Stepper("", value: $model.profile.heightCm, in: 130...220, step: 1).labelsHidden()
                    }
                    HStack {
                        Text("Weight"); Spacer()
                        Text(String(format: "%.1f kg", model.profile.weightKg)).foregroundStyle(Theme.textSecondary)
                        Stepper("", value: $model.profile.weightKg, in: 35...180, step: 0.5).labelsHidden()
                    }
                    Picker("Activity", selection: $model.profile.activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    targetStepper("Calories", $model.profile.dailyCalorieTarget, 25, "kcal")
                    targetStepper("Protein", $model.profile.dailyProteinTarget, 5, "g")
                    targetStepper("Carbs", $model.profile.dailyCarbTarget, 10, "g")
                    targetStepper("Fat", $model.profile.dailyFatTarget, 5, "g")
                    Button {
                        model.profile.recomputeTargetsIfNeeded(force: true)
                        model.profile.targetsManuallyEdited = false
                    } label: {
                        Label("Recalculate from my stats", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.calories)
                    }
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text(model.profile.targetsManuallyEdited
                         ? "Manually adjusted. Tap recalculate to return to your TDEE-based plan."
                         : "Auto-calculated from your body stats and goal (Mifflin-St Jeor TDEE).")
                }

                Section("Coaching") {
                    Toggle("Slow-down reminders", isOn: $model.profile.slowEatingReminders)
                        .tint(Theme.calories)
                }

                Section("AI") {
                    HStack {
                        Text("Live AI")
                        Spacer()
                        Text(model.aiConfigured ? "Connected (Groq)" : "Offline mode")
                            .foregroundStyle(model.aiConfigured ? Theme.positive : Theme.warning)
                    }
                    if !model.aiConfigured {
                        Text("Add your key to Secrets.xcconfig to enable live recognition and coaching.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func targetStepper(_ label: String, _ value: Binding<Double>, _ step: Double, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value.wrappedValue)) \(unit)").foregroundStyle(Theme.textSecondary)
            Stepper("", value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; model.profile.targetsManuallyEdited = true }
            ), in: 0...5000, step: step).labelsHidden()
        }
    }
}
