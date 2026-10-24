import SwiftUI

/// NutriWear design system — premium matte black, high-contrast white type,
/// rounded dark cards with subtle depth, warm macro accents.
enum Theme {
    // Backgrounds
    static let background = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let cardElevated = Color(red: 0.18, green: 0.18, blue: 0.20)
    static let stroke = Color.white.opacity(0.10)

    // Text (high contrast)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.72)
    static let textTertiary = Color(white: 0.48)

    // Macro accents
    static let calories = Color(red: 1.0, green: 0.55, blue: 0.16)   // orange
    static let protein = Color(red: 0.99, green: 0.80, blue: 0.27)   // yellow
    static let carbs = Color(red: 0.33, green: 0.68, blue: 1.0)      // blue
    static let fat = Color(red: 0.76, green: 0.54, blue: 1.0)        // violet

    static let positive = Color(red: 0.36, green: 0.86, blue: 0.56)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.2)

    // Signature gradient (buttons, ring, accents)
    static let accentGradient = LinearGradient(
        colors: [calories, protein],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Subtle top-lit card gradient for depth
    static let cardGradient = LinearGradient(
        colors: [Color(red: 0.145, green: 0.145, blue: 0.16), Color(red: 0.10, green: 0.10, blue: 0.11)],
        startPoint: .top, endPoint: .bottom
    )

    static let cardRadius: CGFloat = 26
}

extension Color {
    static func macro(_ kind: MacroKind) -> Color {
        switch kind {
        case .calories: return Theme.calories
        case .protein: return Theme.protein
        case .carbs: return Theme.carbs
        case .fat: return Theme.fat
        }
    }
}

enum MacroKind: String, CaseIterable {
    case calories = "Calories"
    case protein = "Protein"
    case carbs = "Carbs"
    case fat = "Fat"

    var unit: String { self == .calories ? "kcal" : "g" }
}

// MARK: - Reusable card container

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

extension View {
    /// Applies the app's dark background edge-to-edge, with a faint warm glow top-right.
    func nutriBackground() -> some View {
        self.background(
            ZStack {
                Theme.background
                RadialGradient(
                    colors: [Theme.calories.opacity(0.14), .clear],
                    center: .topTrailing, startRadius: 10, endRadius: 420
                )
            }
            .ignoresSafeArea()
        )
    }
}
