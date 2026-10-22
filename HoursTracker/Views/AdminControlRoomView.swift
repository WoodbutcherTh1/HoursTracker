import SwiftUI

/// Admin → Control room. A live, dark "ops console": aggregate numbers only, the AI and
/// chat kill switches, version spread, and the admin audit log. Motion is decorative and
/// stops under Reduce Motion; every number stays readable as plain text.
struct AdminControlRoomView: View {
    @StateObject private var model = AdminOpsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingSwitch: AdminOpsModel.Switch?

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ControlRoomBackdrop(animated: !reduceMotion)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let notice = model.notice {
                        Text(notice)
                            .font(.footnote.monospaced())
                            .foregroundStyle(ControlRoomPalette.amber)
                    }
                    metricsGrid
                    aiPanel
                    switchesPanel
                    supportPanel
                    versionsPanel
                    auditPanel
                }
                .padding(16)
            }
            .refreshable { await model.refresh() }
        }
        .navigationTitle(L10n.adminControlRoomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task { await model.refresh() }
        .onReceive(refreshTimer) { _ in Task { await model.refresh() } }
        .confirmationDialog(
            pendingSwitch.map { L10n.adminControlRoomConfirmOff($0.title) } ?? "",
            isPresented: Binding(get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.adminControlRoomTurnOff, role: .destructive) {
                if let target = pendingSwitch {
                    Task { await model.setSwitch(target, enabled: false) }
                }
                pendingSwitch = nil
            }
            Button(L10n.editCancel, role: .cancel) { pendingSwitch = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HT // CONTROL")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(ControlRoomPalette.cyan)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Text(context.date, format: .dateTime.hour().minute().second())
                        Text(BlinkingCursor.glyph(at: context.date, animated: !reduceMotion))
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(ControlRoomPalette.dim)
                }
            }
            Spacer()
            StatusPulse(color: model.isHealthy ? ControlRoomPalette.green : ControlRoomPalette.red,
                        animated: !reduceMotion)
            Text(model.isHealthy ? L10n.adminControlRoomOnline : L10n.adminControlRoomOffline)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(model.isHealthy ? ControlRoomPalette.green : ControlRoomPalette.red)
        }
    }

    // MARK: - Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            MetricTile(label: L10n.adminControlRoomActiveToday, value: model.int("active_1d"), accent: ControlRoomPalette.green)
            MetricTile(label: L10n.adminControlRoomActiveWeek, value: model.int("active_7d"), accent: ControlRoomPalette.cyan)
            MetricTile(label: L10n.adminControlRoomNewWeek, value: model.int("new_7d"), accent: ControlRoomPalette.cyan)
            MetricTile(label: L10n.adminControlRoomOnShift, value: model.int("on_shift"), accent: ControlRoomPalette.green)
            MetricTile(label: L10n.adminControlRoomReturning, value: model.int("returning_7d"), accent: ControlRoomPalette.cyan)
            MetricTile(label: L10n.adminControlRoomDevices, value: model.int("devices_total"), accent: ControlRoomPalette.dim)
        }
    }

    // MARK: - AI

    private var aiPanel: some View {
        let used = model.int("ai_today") ?? 0
        let cap = AdminOpsModel.aiDailyCap
        let fraction = min(1, Double(used) / Double(cap))
        let color = fraction > 0.9 ? ControlRoomPalette.red : (fraction > 0.7 ? ControlRoomPalette.amber : ControlRoomPalette.green)
        return ConsolePanel(title: L10n.adminControlRoomAI) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(used)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("/ \(cap) \(L10n.adminControlRoomToday)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ControlRoomPalette.dim)
                Spacer()
                Text("7d: \(model.int("ai_7d") ?? 0)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ControlRoomPalette.dim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fraction)
        }
    }

    // MARK: - Switches

    private var switchesPanel: some View {
        ConsolePanel(title: L10n.adminControlRoomSwitches) {
            ForEach(AdminOpsModel.Switch.allCases) { item in
                let isOn = model.isOn(item)
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        if newValue {
                            Task { await model.setSwitch(item, enabled: true) }
                        } else {
                            pendingSwitch = item
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        Text(isOn ? L10n.adminControlRoomRunning : L10n.adminControlRoomStopped)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(isOn ? ControlRoomPalette.green : ControlRoomPalette.red)
                    }
                }
                .tint(ControlRoomPalette.green)
            }
        }
    }

    // MARK: - Support

    private var supportPanel: some View {
        let unread = model.int("support_unread") ?? 0
        return ConsolePanel(title: L10n.adminSupportTitle) {
            NavigationLink {
                AdminSupportInboxView()
            } label: {
                HStack {
                    if unread > 0 {
                        StatusPulse(color: ControlRoomPalette.amber, animated: !reduceMotion)
                    }
                    Text(L10n.adminControlRoomUnread(unread))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(unread > 0 ? ControlRoomPalette.amber : ControlRoomPalette.dim)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(ControlRoomPalette.dim)
                }
            }
        }
    }

    // MARK: - Versions

    private var versionsPanel: some View {
        let versions = model.versions
        let top = versions.map(\.count).max() ?? 1
        return ConsolePanel(title: L10n.adminControlRoomVersions) {
            if versions.isEmpty {
                Text("—").foregroundStyle(ControlRoomPalette.dim)
            }
            ForEach(versions, id: \.version) { row in
                HStack(spacing: 8) {
                    Text(row.version)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(ControlRoomPalette.cyan.opacity(0.75))
                            .frame(width: max(4, geo.size.width * CGFloat(row.count) / CGFloat(max(top, 1))))
                    }
                    .frame(height: 8)
                    Text("\(row.count)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ControlRoomPalette.dim)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Audit

    private var auditPanel: some View {
        ConsolePanel(title: L10n.adminControlRoomAudit) {
            if model.audit.isEmpty {
                Text(L10n.adminControlRoomAuditEmpty)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ControlRoomPalette.dim)
            }
            ForEach(model.audit) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("> \(entry.summary)")
                        .font(.system(size: 13, design: .monospaced))
                    Text(entry.date, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ControlRoomPalette.dim)
                }
            }
        }
    }
}

// MARK: - Model

@MainActor
final class AdminOpsModel: ObservableObject {
    /// Mirrors AI_GLOBAL_DAILY_CAP in the ai-assist function.
    static let aiDailyCap = 800

    enum Switch: String, CaseIterable, Identifiable {
        case ai = "ai_enabled"
        case chat = "chat_enabled"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ai: return L10n.adminControlRoomSwitchAI
            case .chat: return L10n.adminControlRoomSwitchChat
            }
        }
    }

    struct VersionRow { let version: String; let count: Int }

    struct AuditEntry: Identifiable {
        let id: Int
        let action: String
        let details: [String: Any]
        let date: Date

        var summary: String {
            if action == "set_switch",
               let key = details["key"] as? String,
               let enabled = details["enabled"] as? Bool {
                return "\(key) → \(enabled ? "ON" : "OFF")"
            }
            return action
        }
    }

    @Published private(set) var overview: [String: Any] = [:]
    @Published private(set) var audit: [AuditEntry] = []
    @Published private(set) var notice: String?
    @Published private(set) var isHealthy = true

    private let session: URLSession
    private static let functionURL = SupabaseConfig.projectURL.appendingPathComponent("functions/v1/admin-ops")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func int(_ key: String) -> Int? {
        (overview[key] as? NSNumber)?.intValue
    }

    func isOn(_ item: Switch) -> Bool {
        (overview[item.rawValue] as? Bool) ?? true
    }

    var versions: [VersionRow] {
        guard let rows = overview["versions"] as? [[String: Any]] else { return [] }
        return rows.prefix(6).compactMap { row in
            guard let version = row["version"] as? String, let count = (row["count"] as? NSNumber)?.intValue else { return nil }
            return VersionRow(version: version, count: count)
        }
    }

    func refresh() async {
        if let data = await call(["action": "overview"]) as? [String: Any] {
            withAnimation { overview = data }
            isHealthy = true
        } else {
            isHealthy = false
        }
        if let data = await call(["action": "audit_log"]) as? [String: Any],
           let entries = data["entries"] as? [[String: Any]] {
            audit = entries.compactMap(Self.auditEntry)
        }
    }

    func setSwitch(_ item: Switch, enabled: Bool) async {
        _ = await call(["action": "set_switch", "key": item.rawValue, "enabled": enabled])
        await refresh()
    }

    private static func auditEntry(_ raw: [String: Any]) -> AuditEntry? {
        guard let id = (raw["id"] as? NSNumber)?.intValue, let action = raw["action"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = raw["created_at"] as? String ?? ""
        let date = formatter.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) ?? Date()
        return AuditEntry(id: id, action: action, details: raw["details"] as? [String: Any] ?? [:], date: date)
    }

    private func call(_ body: [String: Any]) async -> Any? {
        guard let token = try? await SupabaseAuthManager.shared.client.auth.session.accessToken else {
            notice = L10n.adminSupportNotSignedIn
            return nil
        }
        var request = URLRequest(url: Self.functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                notice = L10n.adminSupportFailed
                return nil
            }
            notice = nil
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            notice = L10n.adminSupportFailed
            return nil
        }
    }
}

// MARK: - Visual pieces

enum ControlRoomPalette {
    static let background = Color(red: 0.02, green: 0.04, blue: 0.06)
    static let panel = Color(red: 0.05, green: 0.09, blue: 0.12).opacity(0.85)
    static let cyan = Color(red: 0.30, green: 0.85, blue: 0.95)
    static let green = Color(red: 0.25, green: 0.95, blue: 0.55)
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let dim = Color.white.opacity(0.55)
}

private struct ConsolePanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("[ \(title.uppercased()) ]")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(ControlRoomPalette.cyan)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ControlRoomPalette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ControlRoomPalette.cyan.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct MetricTile: View {
    let label: String
    let value: Int?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ControlRoomPalette.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ControlRoomPalette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPulse: View {
    let color: Color
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = animated ? (t.truncatingRemainder(dividingBy: 1.6)) / 1.6 : 0
            ZStack {
                Circle()
                    .stroke(color.opacity(0.6 * (1 - phase)), lineWidth: 1.5)
                    .frame(width: 10 + 14 * phase, height: 10 + 14 * phase)
                Circle().fill(color).frame(width: 8, height: 8)
            }
            .frame(width: 24, height: 24)
        }
        .accessibilityHidden(true)
    }
}

private enum BlinkingCursor {
    static func glyph(at date: Date, animated: Bool) -> String {
        guard animated else { return "_" }
        return Int(date.timeIntervalSinceReferenceDate) % 2 == 0 ? "_" : " "
    }
}

/// Dark grid with a slow scan line. Drawn with Canvas so it stays cheap.
private struct ControlRoomBackdrop: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            Canvas { canvas, size in
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ControlRoomPalette.background))

                let spacing: CGFloat = 28
                var grid = Path()
                var x: CGFloat = 0
                while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
                var y: CGFloat = 0
                while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
                canvas.stroke(grid, with: .color(ControlRoomPalette.cyan.opacity(0.06)), lineWidth: 0.5)

                guard animated else { return }
                let t = context.date.timeIntervalSinceReferenceDate
                let scanY = CGFloat((t.truncatingRemainder(dividingBy: 6)) / 6) * size.height
                let band = CGRect(x: 0, y: scanY - 40, width: size.width, height: 80)
                canvas.fill(
                    Path(band),
                    with: .linearGradient(
                        Gradient(colors: [.clear, ControlRoomPalette.cyan.opacity(0.08), .clear]),
                        startPoint: CGPoint(x: 0, y: band.minY),
                        endPoint: CGPoint(x: 0, y: band.maxY)
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }
}
