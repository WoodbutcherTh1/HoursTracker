import Foundation

/// Live pay for the running shift — the single source for every surface that shows
/// a ticking figure (Home, Watch, widgets, Live Activity). See `LivePayCurve`.
extension AppViewModel {
    /// Sample spacing and how far ahead the curve reaches. 5-minute samples keep the
    /// interpolation error to cents (pay is linear within a tier) while a 16 h reach
    /// covers any real shift; past it the curve extends along its last slope.
    static let livePayCurveStep: TimeInterval = 5 * 60
    static let livePayCurveHorizon: TimeInterval = 16 * 3600

    /// Home's (and the widgets') pay display mode — the same `@AppStorage` key Home's
    /// gross/net picker writes, so every surface shows the figure the user chose.
    static let payDisplayModeKey = "homePayDisplayMode"

    var livePayShowsNet: Bool {
        (UserDefaults.standard.string(forKey: Self.payDisplayModeKey)).flatMap(PayDisplayMode.init(rawValue:)) == .net
    }

    /// Pay earned in the running shift if it ended at `now`, priced by the same engine
    /// as every other figure in the app: the open session is closed off at `now` and
    /// handed to `OvertimeCalculator` in the context of its own day, so the figure
    /// already includes the 125%/150% tiers, rest-day and holiday rates, the travel
    /// allowance, and the tax estimate behind net.
    ///
    /// A break in progress at a workplace that deducts breaks is closed at `now` so pay
    /// stops rising while the worker is on break; the default unpaid break is applied
    /// too — the same calls `clockOut()` makes — so the figure doesn't jump the instant
    /// the shift is actually closed.
    func liveBreakdown(for session: WorkSession, at now: Date, calendar: Calendar = .current) -> DayPayBreakdown {
        let settings = workplaceSettings(for: session.workplaceID)
        var provisional = session
        let end = max(session.clockIn, now)
        provisional.closeOpenBreak(at: end, deductFromPay: !settings.breaksArePaid)
        provisional.clockOut = end
        provisional.applyDefaultBreakIfNeeded(settings: settings)
        return OvertimeCalculator.breakdown(
            for: provisional,
            in: workplaceSessions(for: session.workplaceID),
            settings: settings,
            calendar: calendar
        )
    }

    /// Builds the live pay curve for `session` starting at `now`. Future samples assume
    /// the worker keeps working without another break; any change (a break, clock-out,
    /// a settings edit) rebuilds the curve.
    func makeLivePayCurve(for session: WorkSession, now: Date = Date()) -> LivePayCurve {
        let settings = workplaceSettings(for: session.workplaceID)
        let paidNow = session.paidElapsedSeconds(now: now, breaksArePaid: settings.breaksArePaid)
        let isPaused = session.isOnBreak && !settings.breaksArePaid
        let current = liveBreakdown(for: session, at: now)
        var firstGross = current.grossPay
        var firstNet = current.netPay

        // Clamp the curve's own "now" point to what this shift has already shown —
        // a rebuild (a break starting/ending, a settings edit) re-prices the whole
        // shift from scratch, and that fresh price is not guaranteed to land above
        // what the LAST curve already displayed. Without this, a rebuild could
        // visibly drop the figure a push after it was already shown higher.
        if let mark = livePayHighWaterMark, mark.sessionID == session.id {
            firstGross = max(firstGross, mark.gross)
            firstNet = max(firstNet, mark.net)
        }

        var points = [LivePayCurve.Point(paidSeconds: paidNow, gross: firstGross, net: firstNet)]

        if !isPaused {
            let steps = Int(Self.livePayCurveHorizon / Self.livePayCurveStep)
            points.reserveCapacity(steps + 1)
            for step in 1...steps {
                let ahead = Double(step) * Self.livePayCurveStep
                let breakdown = liveBreakdown(for: session, at: now.addingTimeInterval(ahead))
                points.append(.init(paidSeconds: paidNow + ahead, gross: breakdown.grossPay, net: breakdown.netPay))
            }
        }

        // `OvertimeCalculator` re-prices the whole shift from scratch at every sample
        // (tiers, tax) rather than adding a marginal amount, so two samples a few
        // minutes apart are not guaranteed to come out perfectly monotonic (e.g. a
        // cent of rounding at a tier boundary). Every surface reads this same curve,
        // so clamping it here — pay can only hold or rise, never fall, moving forward
        // in time — is the one place that guarantees it everywhere at once.
        for i in 1..<points.count {
            points[i].gross = max(points[i].gross, points[i - 1].gross)
            points[i].net = max(points[i].net, points[i - 1].net)
        }

        livePayHighWaterMark = (sessionID: session.id, gross: points[0].gross, net: points[0].net)

        return LivePayCurve(
            paidClockStart: now.addingTimeInterval(-paidNow),
            pausedPaidSeconds: isPaused ? paidNow : nil,
            points: points,
            currencyCode: settings.currencyCode,
            sessionID: session.id
        )
    }
}
