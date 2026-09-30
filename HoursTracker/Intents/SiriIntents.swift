import AppIntents
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Siri & Shortcuts
//
// App-target intents with spoken answers, exposed to Siri, Spotlight, the Shortcuts
// app and the Action Button through `HoursTrackerShortcuts`. They act through the
// same AppViewModel calls as the in-app buttons (persistence, sync, widgets, Live
// Activity, Watch). Every one needs the iPhone unlocked (`.requiresAuthentication`):
// the data is protected while locked, and pay is never read out on a locked phone.
// The widget / Live Activity buttons keep their own intents in ShiftIntents.swift.

@MainActor
private func loadedViewModel() -> AppViewModel {
    let viewModel = AppViewModel.shared
    viewModel.retryLoadIfNeeded()
    return viewModel
}

private func dialog(_ text: String) -> IntentDialog {
    IntentDialog(stringLiteral: text)
}

/// Ends an intent with a sentence Siri says instead of a result.
private struct SiriMessage: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: text) }
}

// MARK: Shift

struct SiriStartShiftIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Shift"
    static var description = IntentDescription("Clock in and start tracking your shift.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = loadedViewModel()
        let time = AppLocale.makeDateFormatter(timeStyle: .short)
        if let open = viewModel.activeSession {
            let elapsed = SiriReport.clock(hours: open.elapsedSeconds / 3600)
            return .result(dialog: dialog(L10n.siriAlreadyIn(time.string(from: open.clockIn), elapsed)))
        }
        viewModel.clockIn()
        let start = viewModel.activeSession?.clockIn ?? Date()
        return .result(dialog: dialog(L10n.siriClockedIn(time.string(from: start))))
    }
}

struct SiriEndShiftIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Shift"
    static var description = IntentDescription("Clock out and hear how your shift went.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let viewModel = loadedViewModel()
        guard let open = viewModel.activeSession else {
            return .result(dialog: dialog(L10n.siriNotClockedIn), view: SiriSnippet(title: L10n.siriNotClockedIn))
        }
        let id = open.id
        // Siri says the summary itself — no "Shift complete" notification on top.
        viewModel.clockOut(notifySummary: false)
        guard let closed = viewModel.sessions.first(where: { $0.id == id }),
              let clockOut = closed.clockOut else {
            return .result(dialog: dialog(L10n.sumTitle), view: SiriSnippet(title: L10n.sumTitle))
        }
        let breakdown = viewModel.lastCompletedBreakdown ?? viewModel.breakdown(for: closed)
        let hours = SiriReport.clock(hours: closed.effectiveHours)
        let pay = SiriReport.payText(breakdown, showsNet: viewModel.livePayShowsNet, hidden: WidgetBridge.hidePay)
        let sentence = pay.map { L10n.siriClockedOut(hours, $0) } ?? L10n.siriClockedOutNoPay(hours)
        let time = AppLocale.makeDateFormatter(timeStyle: .short)
        let snippet = SiriSnippet(
            title: L10n.sumTitle,
            value: pay,
            rows: [
                (L10n.historyTotalHours, hours),
                (L10n.gridColIn, time.string(from: closed.clockIn)),
                (L10n.gridColOut, time.string(from: clockOut))
            ]
        )
        return .result(dialog: dialog(sentence), view: snippet)
    }
}

struct SiriStartBreakIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Break"
    static var description = IntentDescription("Pause your shift for a break.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = loadedViewModel()
        guard viewModel.activeSession != nil else { return .result(dialog: dialog(L10n.siriNotClockedIn)) }
        guard !viewModel.isOnBreak else { return .result(dialog: dialog(L10n.siriAlreadyOnBreak)) }
        viewModel.startBreak()
        return .result(dialog: dialog(L10n.siriBreakStarted))
    }
}

struct SiriEndBreakIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Break"
    static var description = IntentDescription("Back to work after your break.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = loadedViewModel()
        guard viewModel.activeSession != nil else { return .result(dialog: dialog(L10n.siriNotClockedIn)) }
        guard viewModel.isOnBreak else { return .result(dialog: dialog(L10n.siriNotOnBreak)) }
        viewModel.endBreak()
        return .result(dialog: dialog(L10n.siriBreakEnded))
    }
}

struct SiriShiftStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Shift Status"
    static var description = IntentDescription("Hear whether you're clocked in, for how long, and what you've earned so far.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let viewModel = loadedViewModel()
        guard let open = viewModel.activeSession else {
            let report = SiriReport(sessions: viewModel.workSessions, settings: viewModel.activeSettings)
            let today = report.totalsSentence(
                for: .today, showsNet: viewModel.livePayShowsNet, payHidden: WidgetBridge.hidePay
            )
            let sentence = L10n.siriNotClockedIn + " " + today
            return .result(dialog: dialog(sentence), view: SiriSnippet(title: L10n.siriNotClockedIn, value: nil, rows: []))
        }
        let now = Date()
        let time = AppLocale.makeDateFormatter(timeStyle: .short).string(from: open.clockIn)
        let paidSeconds = open.paidElapsedSeconds(now: now, breaksArePaid: viewModel.workplaceSettings(for: open.workplaceID).breaksArePaid)
        let elapsed = SiriReport.clock(hours: paidSeconds / 3600)
        let breakdown = viewModel.liveBreakdown(for: open, at: now)
        let pay = SiriReport.payText(breakdown, showsNet: viewModel.livePayShowsNet, hidden: WidgetBridge.hidePay)
        let sentence = pay.map { L10n.siriStatusWorkingPay(time, elapsed, $0) } ?? L10n.siriStatusWorking(time, elapsed)
        let snippet = SiriSnippet(
            title: open.isOnBreak ? L10n.homeOnBreak : L10n.homeClockedIn,
            value: pay,
            rows: [(L10n.gridColIn, time), (L10n.historyTotalHours, elapsed)]
        )
        return .result(dialog: dialog(sentence), view: snippet)
    }
}

// MARK: Earnings

enum SiriPeriod: String, AppEnum {
    case today, thisWeek, thisMonth, lastMonth

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static var caseDisplayRepresentations: [SiriPeriod: DisplayRepresentation] = [
        .today: "Today",
        .thisWeek: "This Week",
        .thisMonth: "This Month",
        .lastMonth: "Last Month"
    ]

    var reportPeriod: SiriReport.Period {
        switch self {
        case .today: return .today
        case .thisWeek: return .thisWeek
        case .thisMonth: return .thisMonth
        case .lastMonth: return .lastMonth
        }
    }
}

struct SiriEarningsIntent: AppIntent {
    static var title: LocalizedStringResource = "Hours and Earnings"
    static var description = IntentDescription("Hear your hours and estimated pay for today, this week or a month.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @Parameter(title: "Period", default: .thisMonth)
    var period: SiriPeriod

    static var parameterSummary: some ParameterSummary {
        Summary("Hours and earnings for \(\.$period)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let viewModel = loadedViewModel()
        let report = SiriReport(sessions: viewModel.workSessions, settings: viewModel.activeSettings)
        let showsNet = viewModel.livePayShowsNet
        let sentence = report.totalsSentence(for: period.reportPeriod, showsNet: showsNet, payHidden: WidgetBridge.hidePay)
        let totals = report.totals(for: period.reportPeriod)
        let pay = totals.breakdown.flatMap { SiriReport.payText($0, showsNet: showsNet, hidden: WidgetBridge.hidePay) }
        let snippet = SiriSnippet(
            title: SiriReport.periodName(period.reportPeriod),
            value: pay,
            rows: [
                (L10n.historyTotalHours, SiriReport.clock(hours: totals.hours)),
                (L10n.historyDaysWorked, "\(totals.shifts)")
            ]
        )
        return .result(dialog: dialog(sentence), view: snippet)
    }
}

// MARK: Export

enum SiriExportFormat: String, AppEnum {
    case pdf, csv

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static var caseDisplayRepresentations: [SiriExportFormat: DisplayRepresentation] = [
        .pdf: "PDF",
        .csv: "CSV"
    ]

    var exportFormat: ExportFormat { self == .pdf ? .pdf : .csv }
    var contentType: UTType { self == .pdf ? .pdf : .commaSeparatedText }
}

struct SiriExportReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Report"
    static var description = IntentDescription("Create a hours report file you can share or save.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @Parameter(title: "Period", default: .thisMonth)
    var period: SiriPeriod

    @Parameter(title: "Format", default: .pdf)
    var format: SiriExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$period) as \(\.$format)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let viewModel = loadedViewModel()
        let report = SiriReport(sessions: viewModel.workSessions, settings: viewModel.activeSettings)
        let name = SiriReport.periodName(period.reportPeriod)
        guard let interval = report.interval(for: period.reportPeriod),
              report.totals(for: period.reportPeriod).shifts > 0 else {
            throw SiriMessage(text: L10n.siriExportEmpty(name))
        }
        // `.custom`'s end is the last day, inclusive.
        let lastDay = interval.end.addingTimeInterval(-1)
        let url = try viewModel.export(range: .custom(from: interval.start, to: lastDay), format: format.exportFormat)
        let data = try Data(contentsOf: url)
        let file = IntentFile(data: data, filename: url.lastPathComponent, type: format.contentType)
        return .result(value: file, dialog: dialog(L10n.siriExportDone(name)))
    }
}

// MARK: Ask

/// "Ask HoursTracker": the in-app assistant by voice. Siri asks what you want to
/// know, the question goes through the same planner + engine as the chat, and the
/// answer comes only from your own data.
struct SiriAskIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask HoursTracker"
    static var description = IntentDescription("Ask about your hours, overtime, pay or payslips.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static var openAppWhenRun = false

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What would you like to know?"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let viewModel = loadedViewModel()
        let router = AssistantLLMRouter.default()
        guard router.isConfigured else {
            let text = L10n.assistantNotConfigured
            return .result(dialog: dialog(text), view: SiriSnippet(title: text, value: nil, rows: []))
        }
        let settings = viewModel.activeSettings
        let sessions = viewModel.workSessions
        let answer: AssistantAnswer
        do {
            let plan = try await router.plan(question: question, context: .current())
            answer = AssistantEngine(settings: settings, sessions: sessions).resolve(plan: plan)
        } catch let error as ScannerLLMError {
            let text = AssistantFailure(error).message
            return .result(dialog: dialog(text), view: SiriSnippet(title: text, value: nil, rows: []))
        } catch {
            let text = AssistantFailure.network.message
            return .result(dialog: dialog(text), view: SiriSnippet(title: text, value: nil, rows: []))
        }
        var spoken = answer.headline
        if !answer.rows.isEmpty, answer.rows.count <= 4 {
            spoken += " " + answer.rows.map { "\($0.label): \($0.value)" }.joined(separator: ", ")
        }
        let snippet = SiriSnippet(
            title: answer.headline,
            value: nil,
            rows: answer.rows.prefix(6).map { ($0.label, $0.value) },
            footnote: answer.scope ?? answer.note
        )
        return .result(dialog: dialog(spoken), view: snippet)
    }
}

// MARK: - Snippet

/// The card Siri shows under its answer: a title, an optional big figure and a few
/// labeled rows, in the app's accent.
struct SiriSnippet: View {
    let title: String
    var value: String?
    var rows: [(String, String)] = []
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HomeAccentTheme.shared.accent)
                Text(title)
                    .font(.headline)
                    .lineLimit(3)
            }
            if let value {
                Text(verbatim: value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HomeAccentTheme.shared.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: row.1)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
