import Foundation

/// Everything the model is told. Note what is *not* here: no sessions, no pay, no
/// employer, no name, no payslips. The assistant sends the question and today's date,
/// gets back the name of a tool to run, and does all the work on-device against the
/// user's own data. Choosing a tool is the only thing the network is used for.
struct AssistantPlannerContext: Equatable {
    /// `"YYYY-MM-DD"` — so relative phrasing like "this month" can be resolved.
    let today: String
    /// Weekday name for today, for "last Sunday"-style questions.
    let weekday: String

    static func current(now: Date = Date(), calendar: Calendar = .current) -> AssistantPlannerContext {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.calendar = Calendar(identifier: .gregorian)
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.dateFormat = "EEEE"

        return AssistantPlannerContext(
            today: dayFormatter.string(from: now),
            weekday: weekdayFormatter.string(from: now)
        )
    }
}

/// A model that turns a question into an `AssistantPlan` — and nothing else.
protocol AssistantLLMProviding: Sendable {
    var name: String { get }
    func plan(question: String, context: AssistantPlannerContext) async throws -> AssistantPlan
}

/// The single prompt both providers send. Kept in one place so the tool list can't drift
/// between them, and written as "pick a tool", never as "answer the user" — the model is
/// given no opportunity to produce prose that could reach the screen.
enum AssistantPrompt {
    /// Hard ceiling on the question we forward. Long pasted text is a prompt-injection
    /// surface and costs the user tokens on their own key for no benefit.
    static let maxQuestionCharacters = 500

    static func instructions(context: AssistantPlannerContext) -> String {
        """
        You route questions for a work-hours tracking app. You do NOT answer questions and \
        you do NOT calculate anything. You reply with ONLY a JSON object choosing one tool.

        Today is \(context.today) (\(context.weekday)). Questions may be in Arabic, Hebrew, \
        or English.

        Schema:
        {"action":"<action>","filters":{...},"pay_mode":"gross|net",\
        "document_format":"pdf|word|markdown|txt","period":"YYYY-MM"}

        Actions:
        - "summarize_hours": how many hours were worked, including overtime tiers.
        - "aggregate_pay": how much was earned. Set pay_mode ("net" unless gross is asked for).
        - "list_sessions": which shifts / what days were worked, and how long each one was —
        including "which day(s) did I work more than N hours" or "which days had overtime"
        (set filters.overtime_tier to "ot125" or "ot150" for that; there is no way to filter
        by a raw hour count, so overtime tier is the closest real match — never route this
        to "list_days_without_sessions", which means the opposite: days with NO shift at all).
        - "list_days_without_sessions": days with NO shift at all (a day off / not worked).
        Set filters.month. Do NOT use this for "which days did I work a lot" — that is
        "list_sessions".
        - "generate_document": the user wants a file / report / export. Set document_format \
        ("pdf" unless another is named).
        - "find_payslip": the user wants a payslip (תלוש / قسيمة راتب) they already uploaded. \
        Set "period" to YYYY-MM.
        - "out_of_scope": anything this app has no data for — weather, news, general chat, \
        advice, or any question not about this user's own recorded work hours, pay, or payslips.

        Filters (all optional, omit any that do not apply; omit all of them for "all time"):
        - "month": "YYYY-MM"
        - "start_date" / "end_date": "YYYY-MM-DD", inclusive
        - "clock_in_after" / "clock_in_before": "HH:MM", 24-hour, for questions about \
        evening/night/morning shifts
        - "overtime_tier": "regular" | "ot125" | "ot150"
        - "day_type": "regular" | "restDay" | "holiday" | "sick"

        Rules:
        - Return the JSON object only. No markdown, no explanation, no other text.
        - Never invent dates, hours, or amounts. You have no access to the user's data.
        - When unsure whether a question is about this app, choose "out_of_scope".
        - When unsure between two actions, prefer the one whose one-line description above \
        most literally matches the question's own wording, and never pick an action whose \
        description contradicts the question (e.g. a question about days that WERE worked \
        must never resolve to the action for days that were NOT worked).
        """
    }

    /// Trimmed and length-capped question text.
    static func sanitize(question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxQuestionCharacters))
    }
}
