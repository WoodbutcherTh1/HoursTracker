import SwiftUI

/// Month + year only — no day — for “export a full month”.
///
/// Deliberately NOT a `Picker`/`Menu` (both draw their selected-value text in the
/// ambient tint, which can be the user's personalized Green accent) and NOT a
/// `confirmationDialog` either — with 12 months + up to 8 years as plain action-sheet
/// rows, iOS renders a massive, nearly full-screen list. A small `.sheet` with its own
/// fixed height and a 3-column month grid stays compact regardless of item count.
struct MonthYearPicker: View {
    @Binding var selection: Date

    private let calendar = Calendar.current
    private let months: [Int] = Array(1...12)
    private var years: [Int] {
        let current = calendar.component(.year, from: Date())
        return Array((current - 6)...(current + 1))
    }

    @State private var showPickerSheet = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showPickerSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(monthName(calendar.component(.month, from: selection)))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(String(calendar.component(.year, from: selection)))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocale.tr("export.monthYear"))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showPickerSheet) {
            MonthYearPickerSheet(selection: $selection, months: months, years: years, monthName: monthName)
                .presentationDetents([.height(350)])
        }
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        guard let date = calendar.date(from: components) else { return "\(month)" }
        return AppLocale.makeDateFormatter(template: "MMMM").string(from: date)
    }
}

/// Compact bottom sheet: a 3-column month grid above a standard year `Picker`.
private struct MonthYearPickerSheet: View {
    @Binding var selection: Date
    let months: [Int]
    let years: [Int]
    let monthName: (Int) -> String

    private let calendar = Calendar.current
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var selectedMonth: Int { calendar.component(.month, from: selection) }
    private var selectedYear: Int { calendar.component(.year, from: selection) }

    var body: some View {
        VStack(spacing: 16) {
            Text(AppLocale.tr("export.monthYear"))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 12)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(months, id: \.self) { month in
                    Button {
                        selection = date(year: selectedYear, month: month)
                    } label: {
                        Text(monthName(month))
                            .font(.subheadline.weight(month == selectedMonth ? .bold : .regular))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(month == selectedMonth ? Color(hex: "00E5FF").opacity(0.25) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(month == selectedMonth ? Color(hex: "00E5FF") : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)

            Picker(AppLocale.tr("export.year"), selection: Binding(
                get: { selectedYear },
                set: { selection = date(year: $0, month: selectedMonth) }
            )) {
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(year).foregroundColor(.white)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 110)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "0D0D0D").ignoresSafeArea())
        // Forces every native control in this sheet (the wheel Picker's selected-row
        // text in particular) to render white instead of the ambient personalized
        // accent — the exact issue that made the old confirmationDialog render green.
        .tint(.white)
    }

    private func date(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? selection
    }
}
