import Foundation

/// Syncs a signed-in user's profile + meals to Supabase via PostgREST.
///
/// Uses one row per user in a `user_data` table (protected by row-level
/// security keyed on auth.uid()):
///
///   create table user_data (
///     id uuid primary key references auth.users on delete cascade,
///     profile jsonb,
///     meals jsonb,
///     updated_at timestamptz default now()
///   );
///   alter table user_data enable row level security;
///   create policy "own data" on user_data
///     for all using (auth.uid() = id) with check (auth.uid() = id);
@MainActor
final class UserSyncClient {
    struct Remote { var profile: UserProfile?; var meals: [Meal]? }

    private let auth: AuthService
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init(auth: AuthService) { self.auth = auth }

    /// Fetch the user's stored profile + meals, if any.
    func fetch() async -> Remote? {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey,
              let session = auth.session else { return nil }
        let url = URL(string: "\(base)/rest/v1/user_data?id=eq.\(session.userID)&select=profile,meals")!
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else {
            return nil
        }
        var remote = Remote()
        if let profileObj = row["profile"], !(profileObj is NSNull),
           let pData = try? JSONSerialization.data(withJSONObject: profileObj) {
            remote.profile = try? decoder.decode(UserProfile.self, from: pData)
        }
        if let mealsObj = row["meals"], !(mealsObj is NSNull),
           let mData = try? JSONSerialization.data(withJSONObject: mealsObj) {
            remote.meals = try? decoder.decode([Meal].self, from: mData)
        }
        return remote
    }

    /// Upsert the user's profile + meals.
    func push(profile: UserProfile, meals: [Meal]) async {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey,
              let session = auth.session else { return }
        guard
            let profileData = try? encoder.encode(profile),
            let mealsData = try? encoder.encode(meals),
            let profileJSON = try? JSONSerialization.jsonObject(with: profileData),
            let mealsJSON = try? JSONSerialization.jsonObject(with: mealsData)
        else { return }

        let payload: [String: Any] = [
            "id": session.userID,
            "profile": profileJSON,
            "meals": mealsJSON,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        let url = URL(string: "\(base)/rest/v1/user_data")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        // Upsert: insert or update the existing row for this user.
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)
    }
}
