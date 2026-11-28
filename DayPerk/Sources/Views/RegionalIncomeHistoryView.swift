import SwiftUI

struct RegionalIncomeRecord: Codable, Identifiable {
    var id = UUID()
    var region: PayrollRegion
    var currency: String
    var month: String
    var gross: Double
    var tax: Double
    var employeeContributions: Double
    var net: Double { max(0, gross - tax - employeeContributions) }
    func validate() throws {
        guard SupportedCurrency(rawValue: currency) != nil, month.count == 7,
              ChinaHolidayCalendar.date(month + "-01") != nil,
              [gross, tax, employeeContributions].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1e12 }),
              tax + employeeContributions <= gross else { throw DayPerkInputError(message: L10n.text("ui.invalid_reported_income_or_deductio.c0cc2d05")) }
    }
}

struct RegionalIncomeHistoryView: View {
    @ObservedObject var model: DayPerkModel
    @State private var records: [RegionalIncomeRecord] = []
    @State private var date = Date()
    @State private var gross: Double = 0
    @State private var tax: Double = 0
    @State private var contributions: Double = 0
    @State private var error = ""
    private let key = "dayperkInternationalIncomeRecords"
    private var filtered: [RegionalIncomeRecord] { records.filter { $0.region == model.regional.region && $0.currency == model.activeCurrencyCode }.sorted { $0.month > $1.month } }
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    BrewDatePicker(title: L10n.text("ui.reporting_month.04bf8d83"), selection: $date, calendar: model.workCalendar, monthsOnly: true)
                    Button(L10n.text("ui.save_record.0ad417a9"), systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly).help(L10n.text("ui.save_record.0ad417a9"))
                        .buttonStyle(BrewButtonStyle(prominent: true)).disabled(!model.access.settingsUnlocked || model.privacy.isPrivacyModeEnabled)
                }
                field(L10n.text("ui.actual_gross_pay.5f0e8273"), value: $gross)
                field(L10n.text("ui.actual_tax_paid.16474e07"), value: $tax)
                field(L10n.text("ui.employee_contributions.f40a4a7f"), value: $contributions)
            } header: {
                HStack(spacing: 6) {
                    Text(L10n.text("ui.add_past_income.79c5d643"))
                    InfoHelp(text: L10n.text("ui.keep_actual_payslip_amounts_separat.0ce24cd9")).frame(width: 18, height: 18)
                }
            }
            Section {
                Grid(horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow { Text(L10n.text("ui.reporting_month.04bf8d83")); Text(L10n.text("ui.actual_gross_pay.5f0e8273")); Text(L10n.text("ui.actual_tax_paid.16474e07")); Text(L10n.text("ui.estimated_monthly_net.5949c66d")) }.font(.caption).foregroundStyle(.secondary)
                    ForEach(filtered) { row in
                        GridRow {
                            Text(row.month)
                            Text(money(row.gross))
                            Text(money(row.tax))
                            Text(money(row.net))
                        }
                    }
                }.frame(maxWidth: .infinity).monospacedDigit()
            } header: { Text(model.activeCurrencyCode + " · " + L10n.text(model.regional.region.name)) }
        }.formStyle(.grouped).actionFeedback($error, isError: true).onAppear {
            records = UserDataStore.shared.data(forKey: key).flatMap { try? JSONDecoder().decode([RegionalIncomeRecord].self, from: $0) } ?? []
        }
    }
    private func field(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent {
            if model.privacy.isPrivacyModeEnabled { Text("•••") }
            else { TextField("0", value: value, format: .number.grouping(.never).precision(.fractionLength(0 ... 2))).labelsHidden().accessibilityLabel(title).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 150) }
        } label: { Text(L10n.text(title)) }
    }
    private func money(_ value: Double) -> String { model.privacy.isPrivacyModeEnabled ? "•••" : model.currency.formatAmount(value) }
    private func save() {
        do {
            guard model.access.settingsUnlocked && !model.privacy.isPrivacyModeEnabled else { return }
            let month = String(WorkPlan.dayKey(date, calendar: model.workCalendar).prefix(7))
            let row = RegionalIncomeRecord(region: model.regional.region, currency: model.activeCurrencyCode, month: month,
                gross: gross, tax: tax, employeeContributions: contributions)
            try row.validate()
            let replacement = records.filter { !($0.region == row.region && $0.currency == row.currency && $0.month == row.month) } + [row]
            UserDataStore.shared.set(try JSONEncoder().encode(replacement), forKey: key)
            records = replacement; error = ""; ActionToastCenter.shared.show(L10n.text("action.saved"))
        } catch { self.error = error.localizedDescription }
    }
}
