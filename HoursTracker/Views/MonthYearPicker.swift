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
        HStack(spacing: 8) {
            Picker(selection: monthBinding) {
                ForEach(months, id: \.self) { month in
                    Text(monthName(month)).tag(month)
                }
            } label: {
                Text(AppLocale.tr("export.month"))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(AppLocale.tr("export.month"))

            Picker(selection: yearBinding) {
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            } label: {
                Text(AppLocale.tr("export.year"))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(AppLocale.tr("export.year"))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocale.tr("export.monthYear"))
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
        return AppLocale.makeDateFormatter(template: "MMMM").string(from: date)
    }
}
