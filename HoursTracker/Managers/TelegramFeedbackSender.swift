import Foundation

enum TelegramFeedbackSendResult: Equatable {
    case success
    case notConfigured
    case failure
}

/// Sends a feedback report — and, optionally, a small text-log attachment —
/// through the `submit-feedback` Supabase Edge Function, which holds the
/// real Telegram bot token/chat id server-side (see
/// `supabase/functions/submit-feedback`) and forwards to the Bot API.
enum TelegramFeedbackSender {
    static func send(_ text: String, session: URLSession = .shared) async -> TelegramFeedbackSendResult {
        await post(body: ["text": text], session: session)
    }

    /// Uploads a file as a base64 payload. Best-effort: called only after the main
    /// feedback message already went through, so a failure here never blocks the user.
    static func sendDocument(
        fileURL: URL,
        caption: String,
        session: URLSession = .shared
    ) async -> TelegramFeedbackSendResult {
        guard let fileData = try? Data(contentsOf: fileURL) else { return .failure }
        return await post(
            body: [
                "documentBase64": fileData.base64EncodedString(),
                "documentName": fileURL.lastPathComponent,
                "caption": caption
            ],
            session: session
        )
    }

    private static func post(body: [String: String], session: URLSession) async -> TelegramFeedbackSendResult {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .failure }

        var request = URLRequest(url: TelegramFeedbackConfig.functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(TelegramFeedbackConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        request.httpBody = data

        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            if http.statusCode == 503 { return .notConfigured }
            guard (200..<300).contains(http.statusCode) else { return .failure }
            guard
                let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                json["success"] as? Bool == true
            else {
                return .failure
            }
            return .success
        } catch {
            return .failure
        }
    }
}
