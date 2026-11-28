import SwiftUI

struct ChinaContributionPreview: View {
    let template: CityPayrollTemplate
    @ObservedObject private var language = LocalizationManager.shared
    var body: some View {
        let rows = [(L10n.text("ui.pension.4bf5576e"), "pension", "employerPension"), (L10n.text("ui.medical.0aeb6f60"), "medical", "employerMedical"), (L10n.text("ui.unemployment.9fa4c944"), "unemployment", "employerUnemployment"), (L10n.text("ui.maternity.15c4da9a"), "", "employerMaternity"), (L10n.text("ui.work_injury.9e99ad52"), "", "employerInjury"), (L10n.text("ui.housing_fund.397c8572"), "fundRate", "employerFundRate")]
        func percentage(_ key: String, employee: Bool) -> String {
            guard !key.isEmpty else { return "—" }
            return template.values[key].map { "\($0.formatted(.number.locale(language.currentLocale)))%" } ?? L10n.text(employee ? L10n.text("ui.current_setting.657662d5") : L10n.text("ui.employer_specific.4d3bdb0f"))
        }
        func baseRange(_ lower: String, _ upper: String) -> String {
            template.values[upper].map { "\((template.values[lower] ?? 0).formatted(.number.locale(language.currentLocale)))–\($0.formatted(.number.locale(language.currentLocale)))" } ?? L10n.text("ui.current_setting.657662d5")
        }
        return Grid(horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text(L10n.text("ui.contribution.748e1333")).frame(maxWidth: .infinity, alignment: .center)
                Text(L10n.text("ui.employee.15dec507")).frame(maxWidth: .infinity, alignment: .center)
                Text(L10n.text("ui.employer.80b19d68")).frame(maxWidth: .infinity, alignment: .center)
            }.font(.caption).foregroundStyle(.secondary)
            Divider().gridCellColumns(3)
            ForEach(rows, id: \.0) { title, personal, employer in
                GridRow {
                    Text(L10n.text(template.values["medicalIncludesMaternity"] == 1 && title == L10n.text("ui.maternity.15c4da9a") ? L10n.text("ui.maternity_included.4d428d44") : template.values["medicalIncludesMaternity"] == 1 && title == L10n.text("ui.medical.0aeb6f60") ? L10n.text("ui.medical_includes_maternity.da62a117") : title)).frame(maxWidth: .infinity, alignment: .center)
                    Text(percentage(personal, employee: true)).frame(maxWidth: .infinity, alignment: .center)
                    Text(percentage(employer, employee: false)).frame(maxWidth: .infinity, alignment: .center)
                }.monospacedDigit()
            }
            if (template.values["fundSupplemental"] ?? 0) > 0 || (template.values["employerFundSupplemental"] ?? 0) > 0 {
                GridRow {
                    Text(L10n.text("ui.supplementary_housing_fund.d53e541f")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(percentage("fundSupplemental", employee: true)).frame(maxWidth: .infinity, alignment: .center)
                    Text(percentage("employerFundSupplemental", employee: false)).frame(maxWidth: .infinity, alignment: .center)
                }.monospacedDigit()
            }
            Divider().gridCellColumns(3)
            GridRow {
                Text(L10n.text("ui.social_insurance_base.b1fc5eb5")).frame(maxWidth: .infinity, alignment: .center)
                Text(baseRange("socialMin", "socialMax")).frame(maxWidth: .infinity, alignment: .center)
                Text(baseRange("socialMin", "socialMax")).frame(maxWidth: .infinity, alignment: .center)
            }.monospacedDigit()
            GridRow {
                Text(L10n.text("ui.housing_fund_base.8a201445")).frame(maxWidth: .infinity, alignment: .center)
                Text(baseRange("fundMin", "fundMax")).frame(maxWidth: .infinity, alignment: .center)
                Text(baseRange("fundMin", "fundMax")).frame(maxWidth: .infinity, alignment: .center)
            }.monospacedDigit()
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

struct ChinaTaxDisclosure: View {
    var template: CityPayrollTemplate
    @ObservedObject private var language = LocalizationManager.shared
    var body: some View {
        DisclosureGroup(L10n.text("payroll.tax_rules_sources")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("payroll.china_tax_summary")).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text(L10n.text("payroll.china_taxable")); Text(L10n.text("payroll.tax_rate")) }.font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(zip([0, 36_000, 144_000, 300_000, 420_000, 660_000, 960_000], [3, 10, 20, 25, 30, 35, 45])), id: \.0) { lower, rate in
                        GridRow { Text("≥ " + lower.formatted(.number.locale(language.currentLocale))); Text("\(rate)%") }
                    }
                }.frame(maxWidth: .infinity).monospacedDigit()
                ForEach(template.sources) { source in
                    if let url = URL(string: source.url), url.scheme == "https" { Link(L10n.text(source.title), destination: url) }
                }
            }.padding(.vertical, 8)
        }
    }
}
