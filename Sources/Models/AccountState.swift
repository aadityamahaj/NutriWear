import Foundation

/// Which path the user chose on first open: not chosen yet, guest (local only),
/// or signed in (synced to the backend). Mirrors the web app's session model.
enum AccountMode: String, Codable {
    case unchosen
    case guest
    case signedIn
}
