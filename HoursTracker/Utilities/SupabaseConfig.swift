import Foundation

/// Connection details for the HoursTracker Supabase project (account sign-up,
/// profile, and cross-device backup — see `SupabaseAuthManager` and
/// `SupabaseAccountSyncManager`).
///
/// Unlike `TelegramFeedbackConfig`, these values are not secrets: the project
/// URL and publishable (anon) key are meant to ship inside the client app.
/// Every table they can reach is locked down with Postgres Row Level Security
/// scoped to `auth.uid()`, so knowing this key alone grants no access to
/// anyone else's data — that's the whole point of a "publishable" key.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://rocjprrvrvmtisxnvopg.supabase.co")!
    static let publishableKey = "sb_publishable_iej3nZ8AVhyLIjCFzsjC7Q_1KJkIUNU" // gitleaks:allow — publishable key, safe to ship (see doc comment above)
}
