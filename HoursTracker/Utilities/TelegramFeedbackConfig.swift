import Foundation

/// Reads the Telegram bot token / chat id from `LocalSecrets` (a plain Swift
/// constant, see `HoursTracker/Config/LocalSecrets.swift`) — a file that's
/// committed with EMPTY values (this repo is public) and meant to be edited
/// locally only. See that file for the one-time setup, and
/// `TelegramFeedbackSender.swift`'s header for how to get a token from
/// @BotFather and a chat id from `https://api.telegram.org/bot<token>/getUpdates`.
/// Left blank, the feedback sheet tells the user support isn't configured yet
/// instead of silently failing.
enum TelegramFeedbackConfig {
    static var botToken: String {
        LocalSecrets.telegramBotToken
    }

    static var chatID: String {
        LocalSecrets.telegramChatID
    }

    static var isConfigured: Bool {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !token.isEmpty && !chat.isEmpty
    }
}
