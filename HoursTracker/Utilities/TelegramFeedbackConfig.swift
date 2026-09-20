import Foundation

/// The Supabase Edge Function that proxies feedback to Telegram (source at
/// `supabase/functions/submit-feedback`). The bot token / chat id live only
/// as Supabase Edge Function secrets — the app never holds them, so nothing
/// usable against the Telegram Bot API sits in the shipped bundle. The
/// project ref below isn't a secret: it's the same kind of public client
/// endpoint as any Supabase project URL.
enum TelegramFeedbackConfig {
    static let functionURL = URL(
        string: "https://rocjprrvrvmtisxnvopg.supabase.co/functions/v1/submit-feedback"
    )!

    /// Supabase's publishable ("anon") key — satisfies the platform's own JWT
    /// check on the Edge Function invocation. It carries no access beyond what
    /// this project's RLS policies grant the `anon` role, which is nothing on
    /// the tables this function touches server-side.
    // gitleaks:allow — Supabase "anon" key, meant to be public/embedded in clients.
    static let supabaseAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJvY2pwcnJ2cnZtdGlzeG52b3BnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4NTEyNDgsImV4cCI6MjEwNTQyNzI0OH0.DRUxfz2M6CDeuB4qatWlYeqw_7PEqPjrTevyy_GFmn8"
}
