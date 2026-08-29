import Foundation

/// One turn in the assistant conversation.
struct AssistantMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    /// The user's question, or the assistant's headline sentence.
    let text: String
    /// Assistant turns only: the grounded figures, scope, and any attachment.
    var answer: AssistantAnswer?
}

/// Drives the assistant chat sheet.
///
/// The split of responsibilities is the whole point of the feature: `AssistantLLMRouter`
/// decides *which* question is being asked, `AssistantEngine` answers it from the user's
/// own data, and this type only moves messages between them and the screen. It never
/// formats a number itself.
@MainActor
final class AssistantChatViewModel: ObservableObject {
    @Published private(set) var messages: [AssistantMessage] = []
    @Published var draft: String = ""
    @Published private(set) var isThinking = false

    private var router: AssistantLLMRouter
    private var pendingTask: Task<Void, Never>?

    init(router: AssistantLLMRouter = .default()) {
        self.router = router
    }

    /// False when no API key is saved. The chat says so plainly instead of pretending to
    /// work — see the comment on `AssistantLLMRouter` for why there is no offline mode.
    var isConfigured: Bool { router.isConfigured }

    /// Picks up a key added in Settings while the app was already running.
    func refreshConfiguration() {
        router = .default()
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    func send(viewModel: AppViewModel) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        ask(question, viewModel: viewModel)
    }

    /// Used by the suggestion chips, which send their text directly.
    func ask(_ question: String, viewModel: AppViewModel) {
        guard !isThinking else { return }
        messages.append(AssistantMessage(role: .user, text: question))

        guard router.isConfigured else {
            appendFailure(.notConfigured, hint: L10n.assistantNotConfiguredHint)
            return
        }

        isThinking = true
        // Snapshot the data now, on the main actor, so the answer describes the state the
        // question was asked about even if a shift is clocked out while the call is in
        // flight. The engine itself is built after the await, not carried across it.
        let settings = viewModel.settings
        let sessions = viewModel.sessions
        let context = AssistantPlannerContext.current()
        let router = self.router

        pendingTask = Task { [weak self] in
            do {
                let plan = try await router.plan(question: question, context: context)
                guard !Task.isCancelled else { return }
                let engine = AssistantEngine(settings: settings, sessions: sessions)
                self?.append(engine.resolve(plan: plan))
            } catch let error as ScannerLLMError {
                guard !Task.isCancelled else { return }
                self?.appendFailure(AssistantFailure(error))
            } catch {
                guard !Task.isCancelled else { return }
                self?.appendFailure(.network)
            }
        }
    }

    func clear() {
        pendingTask?.cancel()
        pendingTask = nil
        isThinking = false
        messages.removeAll()
    }

    // MARK: - Private

    private func append(_ answer: AssistantAnswer) {
        isThinking = false
        messages.append(
            AssistantMessage(role: .assistant, text: answer.headline, answer: answer)
        )
    }

    private func appendFailure(_ failure: AssistantFailure, hint: String? = nil) {
        isThinking = false
        messages.append(
            AssistantMessage(
                role: .assistant,
                text: failure.message,
                answer: AssistantAnswer(headline: failure.message, note: hint)
            )
        )
    }
}
