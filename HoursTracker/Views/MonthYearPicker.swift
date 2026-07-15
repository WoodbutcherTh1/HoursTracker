import SwiftUI

/// Month + year only — no day — for “export a full month”.
struct MonthYearPicker: View {
    @Binding var selection: Date

    private let calendar = Calendar.current
    private let months: [Int] = Array(1...12)
    private var years: [Int] {
        let current = calendar.component(.year, from: Date())
        return Array((current - 6)...(current + 1))
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker(
                String(localized: "export.month", defaultValue: "Month"),
                selection: monthBinding
            ) {
                ForEach(months, id: \.self) { month in
                    Text(monthName(month)).tag(month)
                }
            }
            .pickerStyle(.menu)

            Picker(
                String(localized: "export.year", defaultValue: "Year"),
                selection: yearBinding
            ) {
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "export.monthYear", defaultValue: "Month and year"))
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: selection) },
            set: { newMonth in
                selection = date(year: calendar.component(.year, from: selection), month: newMonth)
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: selection) },
            set: { newYear in
                selection = date(year: newYear, month: calendar.component(.month, from: selection))
            }
        )
    }

    private func date(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? selection
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        guard let date = calendar.date(from: components) else { return "\(month)" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }
}
