import Foundation

/// Reads the Telegram bot token / chat id from Info.plist at runtime, which in turn
/// come from `HoursTracker/Config/Secrets.xcconfig` — a file that's committed with
/// EMPTY values (this repo is public) and meant to be edited locally only. See that
/// file for the one-time setup, and its header comment for how to get a token from
/// @BotFather and a chat id from `https://api.telegram.org/bot<token>/getUpdates`.
/// Left blank, the feedback sheet tells the user support isn't configured yet
/// instead of silently failing.
enum TelegramFeedbackConfig {
    static var botToken: String {
        (Bundle.main.object(forInfoDictionaryKey: "TelegramBotToken") as? String) ?? ""
    }

    static var chatID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TelegramChatID") as? String) ?? ""
    }

    static var isConfigured: Bool {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        // One-time diagnostic for "feedback says not configured" reports —
        // shows exactly what Bundle.main resolved TelegramBotToken/ChatID to
        // at runtime, so a build-setting substitution problem is visible
        // immediately instead of guessed at. Safe to remove once confirmed
        // working; never compiled into Release builds.
        print("🔍 TelegramFeedbackConfig — botToken: '\(token)' (\(token.count) chars), chatID: '\(chat)'")
        #endif
        return !token.isEmpty && !chat.isEmpty
    }
}
