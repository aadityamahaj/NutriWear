import SwiftUI

/// First-open choice: continue as guest (local only) or sign in with a 6-digit
/// email code (synced account). Shown until the user picks. Mirrors the web app.
struct WelcomeGateView: View {
    @EnvironmentObject var model: AppModel

    private enum Step { case choose, email, code }
    @State private var step: Step = .choose
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.calories.opacity(0.16), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                brand
                switch step {
                case .choose: chooseButtons
                case .email: emailCard
                case .code: codeCard
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.accentGradient))
                .shadow(color: Theme.calories.opacity(0.5), radius: 16, y: 6)
            Text("NutriWear")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Your AI eating coach.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var chooseButtons: some View {
        VStack(spacing: 12) {
            Button {
                step = .email
            } label: {
                Text("Sign in with email")
                    .primaryButtonStyle()
            }
            Button {
                model.chooseGuest()
            } label: {
                Text("Continue as guest")
                    .ghostButtonStyle()
            }
            Text(model.authConfigured
                 ? "Sign in to save your food log and preferences across devices. Guest data stays on this device only."
                 : "Guest mode stores data on this device. Email sign-in turns on once the backend is configured.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var emailCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's your email?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("We'll send a 6-digit code — no password needed.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("", text: $email, prompt: Text("you@example.com").foregroundColor(Theme.textTertiary))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
                if let error { errorText(error) }
                Button { Task { await sendCode() } } label: {
                    Text(busy ? "Sending…" : "Send code").primaryButtonStyle()
                }.disabled(busy)
                Button { step = .choose; error = nil } label: {
                    Text("Back").ghostButtonStyle()
                }
            }
        }
    }

    private var codeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter your code")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("We sent a 6-digit code to \(email).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("", text: $code, prompt: Text("123456").foregroundColor(Theme.textTertiary))
                    .keyboardType(.numberPad)
                    .foregroundStyle(Theme.textPrimary)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
                    .onChange(of: code) { _, v in
                        code = String(v.filter(\.isNumber).prefix(6))
                    }
                if let error { errorText(error) }
                Button { Task { await verify() } } label: {
                    Text(busy ? "Verifying…" : "Verify & sign in").primaryButtonStyle()
                }.disabled(busy)
                Button { step = .email; code = ""; error = nil } label: {
                    Text("Use a different email").ghostButtonStyle()
                }
            }
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.warning)
    }

    // MARK: - Actions

    private func sendCode() async {
        error = nil
        let addr = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard addr.contains("@"), addr.contains(".") else {
            error = "Enter a valid email address."; return
        }
        guard model.authConfigured else {
            error = "Sign-in isn't configured yet. You can continue as a guest for now."
            return
        }
        busy = true; defer { busy = false }
        do {
            try await model.auth.sendCode(to: addr)
            step = .code
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        error = nil
        guard code.count == 6 else { error = "Enter the 6-digit code from your email."; return }
        busy = true; defer { busy = false }
        do {
            try await model.auth.verifyCode(email: email.trimmingCharacters(in: .whitespaces).lowercased(), token: code)
            model.didSignIn()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Small styling helpers so the buttons match the app without new components.
private extension Text {
    func primaryButtonStyle() -> some View {
        self.font(.system(size: 16, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    func ghostButtonStyle() -> some View {
        self.font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
    }
}
