import Foundation

/// Fill these in once you create a bot via @BotFather on Telegram: `botToken` is the
/// token BotFather gives you, `chatID` is the numeric id of the chat that should
/// receive feedback (send the bot any message, then check
/// `https://api.telegram.org/bot<token>/getUpdates` for `message.chat.id`).
/// Left blank, the feedback sheet tells the user support isn't configured yet
/// instead of silently failing.
enum TelegramFeedbackConfig {
    static let botToken = ""
    static let chatID = ""

    static var isConfigured: Bool {
        !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
