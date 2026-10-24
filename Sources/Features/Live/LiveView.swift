import SwiftUI

/// Companion "Live" screen. Pairs with the web wearable and shows the active
/// eating session in real time; completed sessions sync into the dashboard.
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var sync: SyncClient

    @State private var urlText: String
    @State private var codeText: String
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(sync: SyncClient) {
        self.sync = sync
        _urlText = State(initialValue: sync.baseURL)
        _codeText = State(initialValue: sync.code)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                pairingCard
                if sync.connected { liveStatus }
                recentSynced
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(ticker) { now = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(sync.connected ? "Connected to wearable" : "Not connected")
                .font(.system(size: 12))
                .foregroundStyle(sync.connected ? Theme.positive : Theme.textTertiary)
        }
        .padding(.top, 12)
    }

    private var pairingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pair with your NutriWear camera")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                field(title: "Server URL", text: $urlText, placeholder: "http://192.168.x.x:3000")
                field(title: "Pairing code", text: $codeText, placeholder: "ABCD", caps: true)

                HStack(spacing: 10) {
                    Button {
                        sync.configure(baseURL: urlText, code: codeText)
                        sync.connect()
                    } label: {
                        Text(sync.connected ? "Reconnect" : "Connect")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if sync.connected {
                        Button { sync.disconnect() } label: {
                            Text("Disconnect")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 13).padding(.horizontal, 16)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                        }
                    }
                }

                if let err = sync.lastError {
                    Text(err).font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String, caps: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.textTertiary))
                .textInputAutocapitalization(caps ? .characters : .never)
                .autocorrectionDisabled()
                .keyboardType(caps ? .asciiCapable : .URL)
                .foregroundStyle(Theme.textPrimary)
                .font(.system(size: 15, weight: .medium))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
        }
    }

    @ViewBuilder
    private var liveStatus: some View {
        if let s = sync.current, s.status == "eating", let start = s.startDate {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                            .opacity(now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                        Text("Eating now").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(durationString(from: start))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.calories)
                            .monospacedDigit()
                    }
                    Text("Detected \(s.detectedBy == "auto" ? "automatically" : "manually") · waiting for “done eating”")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.calories.opacity(0.4), lineWidth: 1))
        } else if sync.current?.status == "ended", let s = sync.current {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive).font(.system(size: 20))
                        Text("Meal logged").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(s.items.first?.name ?? "Meal").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    // "Ate X of Y" consumption story
                    if let eaten = s.eatenCalories, let start = s.startCalories, start > 0 {
                        consumptionBar(eaten: eaten, start: start, leftover: s.leftoverCalories ?? max(0, start - eaten))
                    }
                }
            }
        } else {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "eye").foregroundStyle(Theme.textSecondary)
                    Text("Watching for your meal…").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var recentSynced: some View {
        let synced = model.meals.filter { $0.syncID != nil }.prefix(5)
        return VStack(alignment: .leading, spacing: 10) {
            if !synced.isEmpty {
                Text("Synced from wearable")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(synced)) { meal in
                    MealRow(meal: meal)
                }
            }
        }
    }

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "Ate X of Y kcal" with a proportion bar.
    @ViewBuilder
    private func consumptionBar(eaten: Double, start: Double, leftover: Double) -> some View {
        let frac = start > 0 ? min(1, eaten / start) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Ate \(Int(eaten))").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.calories)
                Text("of \(Int(start)) kcal").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(leftover)) left").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardElevated)
                    Capsule().fill(Theme.accentGradient).frame(width: max(6, geo.size.width * frac))
                }
            }
            .frame(height: 8)
        }
    }
}
