import Foundation

/// Running-shift pay, precomputed by the phone with the real pay engine
/// (`OvertimeCalculator`: overtime tiers, rest-day / holiday rates, travel
/// allowance, net tax estimate) and shared with every surface that shows a live
/// figure — Home, the Watch, the widgets, the Live Activity — so they all show the
/// same number at the same moment instead of each running its own approximation.
///
/// The curve is a list of samples of cumulative pay against **paid** seconds on the
/// shift clock. A surface only needs the time to read it: paid seconds come from
/// `paidClockStart` (the clock-in moved forward by finished unpaid breaks), or stand
/// still at `pausedPaidSeconds` during an unpaid break — so pay freezes during an
/// unpaid break and keeps rising through a paid one, with no extra logic anywhere.
///
/// Compiled into the app, the widget extension and the Watch app (see project.yml):
/// Foundation only, no pay logic — the phone already did that.
struct LivePayCurve: Codable, Equatable {
    struct Point: Codable, Equatable {
        /// Paid seconds on the shift clock.
        var paidSeconds: Double
        var gross: Double
        var net: Double
    }

    /// When the paid clock would have read 0 had it never paused.
    var paidClockStart: Date
    /// Set while an unpaid break is running: the paid clock is stopped here.
    var pausedPaidSeconds: Double?
    /// Ascending by `paidSeconds`; at least one point.
    var points: [Point]
    var currencyCode: String
    /// The open session this curve was built for.
    var sessionID: UUID? = nil

    var isPaused: Bool { pausedPaidSeconds != nil }

    /// Paid seconds on the shift clock at `date`.
    func paidSeconds(at date: Date) -> Double {
        pausedPaidSeconds ?? max(0, date.timeIntervalSince(paidClockStart))
    }

    /// Paid hours on the shift clock at `date`.
    func paidHours(at date: Date) -> Double {
        paidSeconds(at: date) / 3600
    }

    /// Pay at `date`: linear between samples, flat before the first, and extended
    /// along the last segment's slope past the end (a very long shift stays in the
    /// top overtime tier, so that slope is the right one).
    func pay(at date: Date) -> (gross: Double, net: Double) {
        let seconds = paidSeconds(at: date)
        guard let first = points.first else { return (0, 0) }
        if seconds <= first.paidSeconds || points.count == 1 {
            return (first.gross, first.net)
        }
        if let upper = points.firstIndex(where: { $0.paidSeconds >= seconds }) {
            let a = points[upper - 1]
            let b = points[upper]
            return Self.interpolate(a, b, at: seconds)
        }
        let a = points[points.count - 2]
        let b = points[points.count - 1]
        return Self.interpolate(a, b, at: seconds)
    }

    func pay(at date: Date, net: Bool) -> Double {
        let value = pay(at: date)
        return net ? value.net : value.gross
    }

    private static func interpolate(_ a: Point, _ b: Point, at seconds: Double) -> (gross: Double, net: Double) {
        let span = b.paidSeconds - a.paidSeconds
        guard span > 0 else { return (b.gross, b.net) }
        let t = (seconds - a.paidSeconds) / span
        return (a.gross + (b.gross - a.gross) * t, a.net + (b.net - a.net) * t)
    }
}
