import SwiftUI

/// Edit profile, goals, and targets. Backs the personalization requirement.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newAvoidFood = ""
    @State private var showResetConfirm = false

    private func addAvoid() {
        model.addAvoidFood(newAvoidFood)
        newAvoidFood = ""
    }

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

                Section {
                    Toggle("Auto-coach while eating", isOn: $model.profile.coaching.autoCoach)
                        .tint(Theme.calories)
                    Picker("Deliver cues as", selection: $model.profile.coaching.channel) {
                        ForEach(CoachDeliveryChannel.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Proactive coaching")
                } footer: {
                    Text(model.profile.coaching.autoCoach
                         ? "The coach watches your pace and nudges you automatically while you eat."
                         : "Auto-coach is off. Pick the specific cues you still want below.")
                }

                if !model.profile.coaching.autoCoach {
                    Section("Cues to keep") {
                        ForEach(CoachCue.allCases) { cue in
                            Toggle(isOn: cueBinding(cue)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(cue.title, systemImage: cue.icon)
                                    Text(cue.detail)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .tint(Theme.calories)
                        }
                    }
                }

                Section {
                    if model.accountMode == .signedIn, let email = model.auth.session?.email {
                        HStack {
                            Label("Signed in", systemImage: "person.crop.circle.fill")
                            Spacer()
                            Text(email).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    } else {
                        HStack {
                            Label("Guest", systemImage: "person.crop.circle")
                            Spacer()
                            Text("On this device only").font(.footnote).foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Sign out & reset all data", systemImage: "trash")
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Signs you out and erases all meals, preferences, and your avoid list on this device, returning to the welcome screen.")
                }

                if model.accountMode != .signedIn {
                    Section("Sign in") {
                        Button {
                            model.signOut(); dismiss() // returns to the welcome gate to sign in
                        } label: {
                            Label("Sign in to sync", systemImage: "icloud.and.arrow.up")
                                .foregroundStyle(Theme.calories)
                        }
                    }
                }

                Section {
                    if model.profile.avoidFoods.isEmpty {
                        Text("No foods to avoid yet. Rate a meal \"sluggish\" or \"bad\" and its foods land here, or add one below.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(model.profile.avoidFoods, id: \.self) { food in
                            Text(food.capitalized)
                        }
                        .onDelete { indexSet in
                            for i in indexSet { model.removeAvoidFood(model.profile.avoidFoods[i]) }
                        }
                    }
                    HStack {
                        TextField("Add a food to avoid", text: $newAvoidFood)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addAvoid)
                        Button(action: addAvoid) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.calories)
                        }
                        .disabled(newAvoidFood.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Foods to avoid")
                } footer: {
                    Text("When the camera detects one of these, NutriWear warns you to stop.")
                }

                Section("Devices") {
                    NavigationLink {
                        BluetoothView().environmentObject(model)
                    } label: {
                        HStack {
                            Label("Bluetooth devices", systemImage: "sensor.tag.radiowaves.forward.fill")
                            Spacer()
                            if let d = model.bluetooth.connectedDevice {
                                Text(d.name).font(.footnote).foregroundStyle(Theme.positive)
                            } else {
                                Text("Not connected").font(.footnote).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
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
            .alert("Sign out & reset?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Reset everything", role: .destructive) {
                    model.resetAllData()
                    dismiss()
                }
            } message: {
                Text("This erases all your meals, preferences, and avoid list on this device and signs you out. This can't be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Binding for toggling a single proactive cue in the preferences set.
    private func cueBinding(_ cue: CoachCue) -> Binding<Bool> {
        Binding(
            get: { model.profile.coaching.enabledCues.contains(cue) },
            set: { on in
                if on { model.profile.coaching.enabledCues.insert(cue) }
                else { model.profile.coaching.enabledCues.remove(cue) }
            }
        )
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
