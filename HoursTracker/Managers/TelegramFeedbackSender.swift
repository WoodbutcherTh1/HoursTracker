import Foundation
import os

enum TelegramFeedbackSendResult: Equatable {
    case success
    case notConfigured
    case failure
}

/// Sends a feedback report — and, optionally, a small text-log attachment —
/// to the developer's Telegram chat via the Bot API. No backend of our own,
/// just the token/chat id from `TelegramFeedbackConfig`.
enum TelegramFeedbackSender {
    /// Failures are logged here (subsystem `com.hourstracker.app`, category
    /// `telegramFeedback`) with the HTTP status and Telegram's own error
    /// description, so a broken send can be diagnosed from Console.app instead
    /// of surfacing to the user as an opaque failure.
    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "telegramFeedback")

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
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            guard (200..<300).contains(http.statusCode) else {
                logger.error(
                    "sendMessage rejected: HTTP \(http.statusCode, privacy: .public), \(Self.telegramErrorDescription(from: data), privacy: .public)"
                )
                return .failure
            }
            return .success
        } catch {
            logger.error("sendMessage request failed: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    /// Uploads a file via `sendDocument` (multipart/form-data — the Bot API has no
    /// JSON path for file uploads). Best-effort: called only after the main feedback
    /// message already went through, so a failure here never blocks the user.
    static func sendDocument(
        fileURL: URL,
        caption: String,
        session: URLSession = .shared
    ) async -> TelegramFeedbackSendResult {
        guard TelegramFeedbackConfig.isConfigured else { return .notConfigured }
        guard let url = URL(
            string: "https://api.telegram.org/bot\(TelegramFeedbackConfig.botToken)/sendDocument"
        ), let fileData = try? Data(contentsOf: fileURL) else {
            return .failure
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: ["chat_id": TelegramFeedbackConfig.chatID, "caption": caption],
            fileFieldName: "document",
            fileName: fileURL.lastPathComponent,
            fileData: fileData
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            guard (200..<300).contains(http.statusCode) else {
                logger.error(
                    "sendDocument rejected: HTTP \(http.statusCode, privacy: .public), \(Self.telegramErrorDescription(from: data), privacy: .public)"
                )
                return .failure
            }
            return .success
        } catch {
            logger.error("sendDocument request failed: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    /// Telegram error responses look like
    /// `{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}`.
    private static func telegramErrorDescription(from data: Data) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let description = json["description"] as? String
        else { return "no description in response" }
        return description
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields where !value.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
