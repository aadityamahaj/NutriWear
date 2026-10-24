import Foundation

/// Supabase connection settings, injected at build time like the Groq key.
/// Reads SUPABASE_URL and SUPABASE_ANON_KEY from Info.plist (set via
/// Secrets.xcconfig). Auth is only offered when both are present, so the app
/// runs guest-only until configured.
enum SupabaseConfig {
    static var url: String? {
        guard let host = value(for: "SUPABASE_URL") else { return nil }
        // The scheme is omitted in Secrets.xcconfig (xcconfig treats `//` as a
        // comment), so normalize to a full https URL here.
        if host.hasPrefix("http://") || host.hasPrefix("https://") { return host }
        return "https://\(host)"
    }

    static var anonKey: String? {
        value(for: "SUPABASE_ANON_KEY")
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }

    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") || trimmed.contains("your_") { return nil }
        return trimmed
    }
}
