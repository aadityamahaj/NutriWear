import SwiftUI

@main
struct NutriWearApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Force dark, premium look regardless of system setting.
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.calories)
        }
    }
}
