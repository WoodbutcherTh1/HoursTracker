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
        var provisional = session
        let end = max(session.clockIn, now)
        provisional.closeOpenBreak(at: end, deductFromPay: !settings.breaksArePaid)
        provisional.clockOut = end
        provisional.applyDefaultBreakIfNeeded(settings: settings)
        return OvertimeCalculator.breakdown(
            for: provisional,
            in: sessions,
            settings: settings,
            calendar: calendar
        )
    }

    /// Builds the live pay curve for `session` starting at `now`. Future samples assume
    /// the worker keeps working without another break; any change (a break, clock-out,
    /// a settings edit) rebuilds the curve.
    func makeLivePayCurve(for session: WorkSession, now: Date = Date()) -> LivePayCurve {
        let paidNow = session.paidElapsedSeconds(now: now, breaksArePaid: settings.breaksArePaid)
        let isPaused = session.isOnBreak && !settings.breaksArePaid
        let current = liveBreakdown(for: session, at: now)
        var points = [LivePayCurve.Point(paidSeconds: paidNow, gross: current.grossPay, net: current.netPay)]

        if !isPaused {
            let steps = Int(Self.livePayCurveHorizon / Self.livePayCurveStep)
            points.reserveCapacity(steps + 1)
            for step in 1...steps {
                let ahead = Double(step) * Self.livePayCurveStep
                let breakdown = liveBreakdown(for: session, at: now.addingTimeInterval(ahead))
                points.append(.init(paidSeconds: paidNow + ahead, gross: breakdown.grossPay, net: breakdown.netPay))
            }
        }

        return LivePayCurve(
            paidClockStart: now.addingTimeInterval(-paidNow),
            pausedPaidSeconds: isPaused ? paidNow : nil,
            points: points,
            currencyCode: settings.currencyCode,
            sessionID: session.id
        )
    }
}
