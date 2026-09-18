import Foundation

enum TelegramFeedbackSendResult: Equatable {
    case success
    case notConfigured
    case failure
}

/// Sends a feedback report to the developer's Telegram chat via the Bot API's
/// `sendMessage` endpoint — no backend of our own, just the token/chat id from
/// `TelegramFeedbackConfig`.
enum TelegramFeedbackSender {
    static func send(_ text: String, session: URLSession = .shared) async -> TelegramFeedbackSendResult {
        guard TelegramFeedbackConfig.isConfigured else { return .notConfigured }
        guard let url = URL(
            string: "https://api.telegram.org/bot\(TelegramFeedbackConfig.botToken)/sendMessage"
        ) else {
            return .failure
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "chat_id": TelegramFeedbackConfig.chatID,
            "text": text,
            "disable_web_page_preview": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure
        }
        request.httpBody = data

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            return (200..<300).contains(http.statusCode) ? .success : .failure
        } catch {
            return .failure
        }
    }
}
