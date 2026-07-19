import Foundation
import HoursTrackerKit

/// Watch-namespaced strings. Uses an in-module table so watchOS screenshots
/// don't depend on String Catalog copy quirks, then falls back to the catalog.
enum WatchL10n {
    private static let table: [String: [WatchLanguageCode: String]] = [
        "watch.clock.title": [.english: "Clock", .hebrew: "שעון", .arabic: "البصمة", .system: "Clock"],
        "watch.clock.in": [.english: "Clock In", .hebrew: "כניסה", .arabic: "تسجيل دخول", .system: "Clock In"],
        "watch.clock.out": [.english: "Clock Out", .hebrew: "יציאה", .arabic: "تسجيل خروج", .system: "Clock Out"],
        "watch.clock.today": [.english: "Today", .hebrew: "היום", .arabic: "اليوم", .system: "Today"],
        "watch.recent.title": [.english: "Recent", .hebrew: "אחרונים", .arabic: "الأخيرة", .system: "Recent"],
        "watch.recent.empty": [
            .english: "No recent shifts",
            .hebrew: "אין משמרות אחרונות",
            .arabic: "لا ورديات أخيرة",
            .system: "No recent shifts"
        ],
        "watch.format.hours": [.english: "%@ h", .hebrew: "%@ שע׳", .arabic: "%@ س", .system: "%@ h"]
    ]

    private static func lang(for locale: Locale) -> WatchLanguageCode {
        let id = locale.identifier.lowercased()
        if id.hasPrefix("he") || id.contains("_he") || id.contains("-he") { return .hebrew }
        if id.hasPrefix("ar") || id.contains("_ar") || id.contains("-ar") { return .arabic }
        if id.hasPrefix("en") { return .english }
        return WatchScreenshotDemoData.preferredLanguage
    }

    private static func t(_ key: String, locale: Locale) -> String {
        let code = lang(for: locale)
        if let value = table[key]?[code] ?? table[key]?[.english] {
            return value
        }
        let localized = String(localized: String.LocalizationValue(key), locale: locale)
        return localized == key ? key : localized
    }

    static func clockTitle(locale: Locale) -> String { t("watch.clock.title", locale: locale) }
    static func clockIn(locale: Locale) -> String { t("watch.clock.in", locale: locale) }
    static func clockOut(locale: Locale) -> String { t("watch.clock.out", locale: locale) }
    static func todaySummary(locale: Locale) -> String { t("watch.clock.today", locale: locale) }
    static func recentTitle(locale: Locale) -> String { t("watch.recent.title", locale: locale) }
    static func recentEmpty(locale: Locale) -> String { t("watch.recent.empty", locale: locale) }
    static func hoursShort(_ hours: Double, locale: Locale) -> String {
        String(format: t("watch.format.hours", locale: locale), String(format: "%.1f", hours))
    }
    static func elapsed(from start: Date, now: Date, locale: Locale) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
