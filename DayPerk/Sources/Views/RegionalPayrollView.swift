import SwiftUI

enum WorkTimeZoneOptions {
    static let explanationKey = "ui.regional_presets_use_the_local_time.951e9a21"
    static var explanation: String { L10n.text(explanationKey) }
    static let cities = Array(Set(PayrollCatalog.bundled.policies.map(\.timeZone) + ["Asia/Shanghai"])).sorted()
    // 现行民用时区的固定偏移，含南北半球夏令时；不凭空组合十五分钟值。
    static let offsets = (Array(stride(from: -12 * 3600, through: 14 * 3600, by: 3600)) +
        [-570, -210, -150, 210, 270, 330, 390, 570, 630, 345, 525, 765, 825].map { $0 * 60 }).sorted()
    static func label(_ seconds: Int) -> String {
        String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
    }
    static func isFixed(_ identifier: String) -> Bool { identifier == "UTC" || identifier.hasPrefix("GMT") }
    static func fixedIdentifier(_ seconds: Int) -> String? {
        guard offsets.contains(seconds) else { return nil }
        return TimeZone(secondsFromGMT: seconds)?.identifier
    }
}

struct WorkTimeZonePicker: View {
    @Binding var identifier: String
    var preferredCity: String
    private var seconds: Int { TimeZone(identifier: identifier)?.secondsFromGMT() ?? 0 }
    private var fixed: Bool { WorkTimeZoneOptions.isFixed(identifier) }
    private var mode: Binding<Bool> {
        Binding(get: { fixed }, set: { value in
            guard value != fixed else { return }
            if value { identifier = WorkTimeZoneOptions.fixedIdentifier(seconds) ?? "GMT" }
            else { identifier = WorkTimeZoneOptions.cities.contains(preferredCity) ? preferredCity : "Asia/Shanghai" }
        })
    }
    var body: some View {
        HStack(spacing: 8) {
            Picker(L10n.text("ui.time_zone_mode.7760fd87"), selection: mode) {
                Text(L10n.text("ui.common_cities.fbb40c6b")).tag(false)
                Text(L10n.text("ui.utc_offset.3784056b")).tag(true)
            }.labelsHidden().fixedSize()
            if fixed {
                Picker(L10n.text("time_zone.fixed_offset"), selection: Binding(get: { seconds }, set: { offset in
                    if let id = WorkTimeZoneOptions.fixedIdentifier(offset) { identifier = id }
                })) {
                    ForEach(WorkTimeZoneOptions.offsets, id: \.self) { Text(WorkTimeZoneOptions.label($0)).tag($0) }
                }.labelsHidden().monospacedDigit().fixedSize()
            } else {
                Picker(L10n.text("ui.city_time_zone.66ff1401"), selection: $identifier) {
                    ForEach(Array(Set(WorkTimeZoneOptions.cities + [identifier])).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize()
            }
        }
    }
}

struct RegionalPayrollView: View {
    @ObservedObject var model: DayPerkModel
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var region: PayrollRegion
    @State private var input: RegionalPayInput
    @State private var policy: RegionalPayrollPolicy
    @State private var china: DayPerkConfiguration
    @State private var timeZone: String
    private let onApply: () -> Void
    private let onRegionChange: (PayrollRegion) -> Void
    @State private var message = ""
    @State private var isError = false

    init(model: DayPerkModel, initialRegion: PayrollRegion? = nil, onRegionChange: @escaping (PayrollRegion) -> Void = { _ in }, onApply: @escaping () -> Void = {}) {
        self.model = model
        self.onApply = onApply
        self.onRegionChange = onRegionChange
        let selectedRegion = initialRegion ?? model.regional.region
        let selectedPolicy = selectedRegion == model.regional.region ? model.regional.selectedPolicy : PayrollCatalog.bundled.policies(for: selectedRegion).first ?? .custom
        _china = State(initialValue: model.configuration)
        _region = State(initialValue: selectedRegion)
        _input = State(initialValue: model.regional.input)
        _policy = State(initialValue: selectedPolicy)
        _timeZone = State(initialValue: selectedRegion == model.regional.region ? model.regional.timeZoneID : selectedPolicy.timeZone)
    }
    private func text(_ key: String) -> Text { Text(L10n.text(key)) }
    private var canShowAmounts: Bool { model.access.settingsUnlocked && !model.privacy.isPrivacyModeEnabled }
    private var estimate: RegionalPayEstimate? { try? InternationalPayrollCalculator().estimate(input: input, policy: policy) }
    private var choices: [RegionalPayrollPolicy] { PayrollCatalog.bundled.policies(for: region) }
    private var employmentKinds: [PayrollEmploymentKind] { PayrollEmploymentKind.allCases.filter { kind in choices.contains { $0.effectiveEmploymentKind == kind } } }
    private var cityChoices: [RegionalPayrollPolicy] { choices.filter { $0.effectiveEmploymentKind == policy.effectiveEmploymentKind } }
    private func money(_ value: Double) -> String {
        guard canShowAmounts else { return "•••" }
        return value.formatted(.currency(code: policy.currency).locale(localization.currentLocale).precision(.fractionLength(model.currency.displayDecimalPlaces)))
    }
    var body: some View {
        Form {
            Section {
                HStack {
                    text(L10n.text("ui.payroll_region.6e425cd7"))
                    InfoHelp(text: L10n.text("ui.presets_are_editable_starting_point.e4270f35")).frame(width: 18, height: 18)
                    Spacer()
                    Picker("", selection: $region) { ForEach(PayrollRegion.allCases) { text($0.name).tag($0) } }
                        .labelsHidden().accessibilityLabel(L10n.text("ui.payroll_region.6e425cd7")).fixedSize()
                }
                if region != .china {
                    if region != .custom {
                        if employmentKinds.count > 1 {
                            HStack {
                                text(L10n.text("ui.employment_arrangement.bf548d26"))
                                InfoHelp(text: L10n.text("ui.choose_the_legal_income_arrangement.47a8755d")).frame(width: 18, height: 18)
                                Spacer()
                                Picker(selection: Binding(get: { policy.effectiveEmploymentKind }, set: { kind in
                                    if let selected = choices.first(where: { $0.effectiveEmploymentKind == kind && $0.city == policy.city }) ?? choices.first(where: { $0.effectiveEmploymentKind == kind }) {
                                        policy = selected
                                        if kind == .domesticWorker { input.cpfStatus = "foreigner"; input.frequency = .monthly }
                                        else if region == .singapore { input.cpfStatus = "citizen" }
                                        input.declaredContributionsConfirmed = false
                                    }
                                })) { ForEach(employmentKinds) { text($0 == .employee ? "payroll.employee_status" : $0.rawValue).tag($0) } } label: { text(L10n.text("ui.employment_arrangement.bf548d26")) }
                                    .labelsHidden().accessibilityLabel(L10n.text("ui.employment_arrangement.bf548d26")).fixedSize()
                            }
                        }
                        Picker(selection: Binding(get: { policy.id }, set: { id in
                            if let selected = cityChoices.first(where: { $0.id == id }) { policy = selected; timeZone = selected.timeZone }
                        })) { ForEach(cityChoices) { text($0.city).tag($0.id) } } label: { text(L10n.text("ui.city_jurisdiction.3c3b13f6")) }
                    }
                    HStack {
                        text(L10n.text("ui.policy_details.00e33950"))
                        InfoHelp(text: ([policy.validFrom + " – " + policy.validThrough] + policy.assumptions).map { "• " + L10n.text($0) }.joined(separator: "\n\n")).frame(width: 18, height: 18)
                        Spacer()
                        Text("\(policy.taxYear.formatted(.number.grouping(.never))) · \(policy.currency) · \(policy.subdivision)").foregroundStyle(.secondary)
                    }
                    contributionPreview
                }
                HStack {
                    text(L10n.text("ui.work_time_zone.150fd218"))
                    InfoHelp(text: WorkTimeZoneOptions.explanation).frame(width: 18, height: 18)
                    Spacer()
                    WorkTimeZonePicker(identifier: $timeZone, preferredCity: region == .china ? "Asia/Shanghai" : policy.timeZone)
                }
            }
            if region == .china {
                chinaRules
            }
            if region != .china {
                if canShowAmounts {
                    Section {
                        Picker(selection: $input.frequency) { ForEach(PayFrequency.allCases) { text($0.rawValue).tag($0) } } label: { text(L10n.text("ui.pay_frequency.69918bf2")) }
                        number(policy.effectiveEmploymentKind == .selfEmployed ? L10n.text("ui.business_profit_per_period_before_p.3a8b8f24") : L10n.text("ui.gross_pay_per_period.8050bbe1"), value: $input.amount)
                        number(L10n.text("ui.annual_bonus.59651e78"), value: $input.annualBonus)
                        number(L10n.text("ui.hours_per_week.6321dbb4"), value: $input.hoursPerWeek)
                        number(L10n.text("ui.annual_extra_deduction.52d182c0"), value: $input.annualExtraDeduction)
                        if [.singapore, .japan, .southKorea, .germany].contains(region) && policy.effectiveEmploymentKind == .employee {
                            Stepper(value: $input.age, in: 0 ... 120) { Text("\(L10n.text("ui.age.39b7370f")): \(input.age)") }
                        }
                        if [.japan, .southKorea].contains(region) {
                            Stepper(value: $input.dependants, in: 0 ... 30) { Text("\(L10n.text("ui.dependants.6455dd00")): \(input.dependants)") }
                        }
                        Toggle(isOn: $input.isTaxResident) { text(L10n.text("ui.tax_resident.0e0cf0be")) }
                        if region == .newZealand {
                            Toggle(isOn: Binding(get: { input.kiwiSaverEnabled ?? true }, set: { input.kiwiSaverEnabled = $0 })) { text(L10n.text("ui.enrolled_in_kiwisaver.fa6e5125")) }
                            HStack {
                                Toggle(isOn: Binding(get: { input.eligibleForIETC ?? false }, set: { input.eligibleForIETC = $0 })) { text(L10n.text("ui.eligible_for_independent_earner_tax.bda2240a")) }
                                InfoHelp(text: L10n.text("ui.select_ietc_only_if_eligible_for_th.65cc8b5c")).frame(width: 18, height: 18)
                            }
                        }
                        if region == .germany {
                            Toggle(isOn: Binding(get: { input.hasChildren ?? false }, set: { input.hasChildren = $0; if !$0 { input.childrenUnder25 = 0 } })) { text(L10n.text("ui.parent_status_for_care_insurance.f62617da")) }
                            if input.hasChildren == true {
                                Stepper(value: Binding(get: { input.childrenUnder25 ?? 0 }, set: { input.childrenUnder25 = $0 }), in: 0 ... 10) {
                                    Text("\(L10n.text("ui.children_under_25.3957130e")): \(input.childrenUnder25 ?? 0)")
                                }
                            }
                            Toggle(isOn: Binding(get: { input.paysChurchTax ?? false }, set: { input.paysChurchTax = $0 })) { text(L10n.text("ui.pay_church_tax.533dbad1")) }
                        }
                        if region == .australia {
                            Toggle(isOn: $input.includesEmployerBenefit) { text(L10n.text("ui.pay_package_includes_employer_super.b4e4d83b")) }
                            Toggle(isOn: $input.hasPrivateHospitalCover) { text(L10n.text("ui.eligible_private_hospital_cover.a6ffa375")) }
                        }
                        if region == .singapore && policy.effectiveEmploymentKind == .employee {
                            Picker(L10n.text("payroll.cpf"), selection: $input.cpfStatus) {
                                text("payroll.cpf_citizen").tag("citizen"); text(L10n.text("ui.permanent_resident_third_year_onwar.cab0e546")).tag("pr-third"); text("payroll.cpf_foreigner").tag("foreigner")
                            }
                        }
                        if (region == .japan || region == .southKorea) && policy.effectiveEmploymentKind == .employee { number(L10n.text("ui.declared_monthly_social_insurance_b.b71d0947"), value: $input.declaredMonthlySocialBase) }
                        if policy.effectiveEmploymentKind == .selfEmployed {
                            ForEach($policy.contributions) { $rule in
                                number(rule.name, value: Binding(get: { rule.employeeMonthlyAmount ?? 0 }, set: { rule.employeeMonthlyAmount = $0; input.declaredContributionsConfirmed = false }))
                            }
                            Toggle(isOn: Binding(get: { input.declaredContributionsConfirmed ?? false }, set: { input.declaredContributionsConfirmed = $0 })) { text(L10n.text("ui.i_have_entered_my_actual_monthly_co.10ac6ec0")) }
                        }
                        if region == .japan { number(L10n.text("ui.previous_year_gross_pay.82d68d50"), value: $input.previousYearGrossIncome) }
                    } header: { text(L10n.text("ui.gross_pay_per_period.8050bbe1")) }
                    withdrawableBenefitSection
                    Section {
                        if let result = estimate {
                            LabeledContent { Text(money(result.annualGross)) } label: { text(L10n.text("ui.annual_gross_pay.c8ba8c11")) }
                            LabeledContent { Text(money(result.annualIncomeTax)) } label: { text(L10n.text("ui.income_tax.de2ae4a1")) }
                            LabeledContent { Text(money(result.annualRegionalTax)) } label: { text(L10n.text("ui.regional_income_tax.10b35ff3")) }
                            LabeledContent { Text(money(result.employeeContributions)) } label: { text(L10n.text("ui.employee_contributions.f40a4a7f")) }
                            LabeledContent { Text(money(result.employerContributions)) } label: { text(L10n.text("ui.employer_contributions.402dc5da")) }
                            LabeledContent { Text(money(result.cashNet)) } label: { text(L10n.text("ui.estimated_annual_net.10ffab13")) }
                            LabeledContent { Text(money(result.cashNet / 12)).foregroundStyle(model.appearance.theme.color) } label: { text(L10n.text("ui.estimated_monthly_net.5949c66d")) }
                        } else {
                            Text(estimateError).foregroundStyle(.orange)
                        }
                    } header: { HStack { text(L10n.text("ui.preview.324b134f")); InfoHelp(text: L10n.text("ui.all_figures_are_annualized_estimate.8c5bf1b8")).frame(width: 18, height: 18) } }
                } else {
                    Section { SalaryUnlockView(access: model.access, settings: true).frame(height: 200) }
                }
                Section {
                    DisclosureGroup {
                        policyEditor
                    } label: { text(L10n.text("ui.edit_policy.18f41a84")) }
                }
                Section {
                    ForEach(policy.sources) { source in
                        if let url = URL(string: source.url), url.scheme == "https" { Link(L10n.text(source.title), destination: url) }
                    }
                } header: { text(L10n.text("ui.official_sources.0d08e0a9")) }
            }
        }.formStyle(.grouped).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle())
            .scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Spacer()
                        Button { apply() } label: { text(L10n.text("ui.apply_configuration.3f9fa188")) }
                            .buttonStyle(BrewButtonStyle(prominent: true))
                            .disabled(!model.access.settingsUnlocked || model.privacy.isPrivacyModeEnabled)
                    }.padding(14)
                }.background(model.appearance.theme.canvas)
            }
            .actionFeedback($message, isError: isError)
            .onChange(of: region) { _, value in
                if value != .custom { policy = PayrollCatalog.bundled.policies(for: value).first ?? .custom }
                timeZone = value == .china ? "Asia/Shanghai" : policy.timeZone
                onRegionChange(value)
            }
    }
    private var chinaRules: some View {
        Group {
            Section(L10n.text("ui.city_contribution_presets.24e8ec2f")) {
                Picker(L10n.text("ui.city.317f75c9"), selection: Binding(get: { china.payroll.policy.cityTemplateID ?? "beijing" }, set: { id in
                    if let template = CityPayrollTemplates.all.first(where: { $0.id == id }) { china = template.applying(to: china) }
                })) {
                    ForEach(CityPayrollTemplates.all) { Text(L10n.text($0.name)).tag($0.id) }
                }
                if let template = CityPayrollTemplates.all.first(where: { $0.id == (china.payroll.policy.cityTemplateID ?? "beijing") }) {
                    ChinaContributionPreview(template: template)
                }
            }
            if canShowAmounts {
                Section(L10n.text("ui.gross_pay_per_period.8050bbe1")) {
                    number(L10n.text("payroll.china_monthly"), value: $china.baseSalary)
                    number(L10n.text("ui.monthly_additional_deductions.d50efaaa"), value: $china.payroll.monthlySpecialAdditionalDeduction)
                    number(L10n.text("ui.social_insurance_contribution_base.b537e541"), value: $china.payroll.contributionBase)
                    number(L10n.text("ui.housing_fund_contribution_base.662ad43b"), value: $china.payroll.housingFundBase)
                }
            }
            Section(L10n.text("ui.cumulative_tax_withholding.74218954")) {
                Text(L10n.text("payroll.china_tax_summary")).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text(L10n.text("payroll.china_taxable")); Text(L10n.text("payroll.tax_rate")) }.font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(zip([0, 36_000, 144_000, 300_000, 420_000, 660_000, 960_000], [3, 10, 20, 25, 30, 35, 45])), id: \.0) { lower, rate in
                        GridRow { Text("≥ " + lower.formatted(.number.locale(localization.currentLocale))); Text("\(rate)%") }
                    }
                }.frame(maxWidth: .infinity).monospacedDigit()
            }
            if let template = CityPayrollTemplates.all.first(where: { $0.id == (china.payroll.policy.cityTemplateID ?? "beijing") }) {
                Section(L10n.text("ui.official_sources.0d08e0a9")) {
                    ForEach(template.sources) { source in
                        if let url = URL(string: source.url), url.scheme == "https" { Link(L10n.text(source.title), destination: url) }
                    }
                }
            }
        }
    }

    var withdrawableBenefitSection: some View {
        WithdrawableBenefitsSection(model: model, region: region, currency: policy.currency)
            .id(region.rawValue + policy.currency)
    }

    private var estimateError: String {
        do { _ = try InternationalPayrollCalculator().estimate(input: input, policy: policy); return "" }
        catch { return L10n.text(error.localizedDescription) }
    }
    private var contributionPreview: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow { text(L10n.text("ui.contributions.7219a025")); text(L10n.text("ui.employee.14014e6a")); text(L10n.text("ui.employer.54a3b64c")) }.font(.caption).foregroundStyle(.secondary)
            if policy.effectiveEmploymentKind == .domesticWorker {
                GridRow {
                    HStack {
                        Text(L10n.text("payroll.cpf"))
                        InfoHelp(text: L10n.text("ui.migrant_domestic_workers_do_not_con.27481618")).frame(width: 18, height: 18)
                    }
                    Text("0%"); Text("0%")
                }
            }
            ForEach(policy.contributions) { rule in
                GridRow {
                    text(rule.name)
                    Text(rule.employeeMonthlyAmount.map { "\($0.formatted(.number.locale(LocalizationManager.shared.currentLocale))) \(policy.currency)/\(L10n.text("month"))" } ?? (rule.employeeRate * 100).formatted(.number.locale(LocalizationManager.shared.currentLocale)) + "%")
                    Text(rule.employerMonthlyAmount.map { "\($0.formatted(.number.locale(LocalizationManager.shared.currentLocale))) \(policy.currency)/\(L10n.text("month"))" } ?? (rule.employerRate * 100).formatted(.number.locale(LocalizationManager.shared.currentLocale)) + "%")
                }
            }
        }.frame(maxWidth: .infinity).monospacedDigit().padding(.vertical, 8)
    }
    @ViewBuilder private var policyEditor: some View {
        if region == .custom {
            TextField(L10n.text("ui.city_jurisdiction.3c3b13f6"), text: $policy.city)
            Picker(selection: $policy.currency) { ForEach(SupportedCurrency.allCases.filter { $0 != .system }) { Text($0.displayName).tag($0.rawValue) } } label: { text(L10n.text("ui.currency.6f11660c")) }
        } else {
            HStack {
                InfoHelp(text: L10n.text("ui.the_country_module_applies_local_re.47683ccb")).frame(width: 18, height: 18)
                Button { var copy = policy; copy.country = .custom; copy.id = "custom"; region = .custom; policy = copy } label: { text(L10n.text("ui.use_generic_calculation.c4c4898b")) }
            }
        }
        number(L10n.text("ui.tax_allowance.a0787cae"), value: $policy.taxAllowance)
        number(L10n.text("ui.regional_allowance.e87d7e71"), value: $policy.regionalAllowance)
        if region != .germany { bands($policy.taxBands, title: L10n.text("ui.national_tax_bands.bf103afa")) }
        bands($policy.regionalBands, title: L10n.text("ui.regional_tax_bands.e354617b"))
        HStack {
            Text(L10n.text("ui.contributions.7219a025"))
            Spacer()
            Button(L10n.text("ui.add_contribution.3f6ea08f"), systemImage: "plus") {
                policy.contributions.append(ContributionRule(id: UUID().uuidString, name: L10n.text("ui.contributions.7219a025"), employeeRate: 0, employerRate: 0))
            }.labelStyle(.iconOnly).help(L10n.text("ui.add_contribution.3f6ea08f"))
        }
        ForEach($policy.contributions) { $rule in
            DisclosureGroup(L10n.text(rule.name)) {
                TextField(L10n.text("ui.contributions.7219a025"), text: $rule.name)
                percent(L10n.text("ui.employee.c4b9900a"), value: $rule.employeeRate)
                percent(L10n.text("ui.employer.bb57b18e"), value: $rule.employerRate)
                Toggle(isOn: Binding(get: { rule.employeeMonthlyAmount != nil }, set: { rule.employeeMonthlyAmount = $0 ? 0 : nil })) { text(L10n.text("ui.use_fixed_monthly_employee_amount.4e9ccff2")) }
                if rule.employeeMonthlyAmount != nil { number(L10n.text("ui.monthly_employee_amount.f0ccee2b"), value: Binding(get: { rule.employeeMonthlyAmount ?? 0 }, set: { rule.employeeMonthlyAmount = $0 })) }
                Toggle(isOn: Binding(get: { rule.employerMonthlyAmount != nil }, set: { rule.employerMonthlyAmount = $0 ? 0 : nil })) { text(L10n.text("ui.use_fixed_monthly_employer_amount.ea656a87")) }
                if rule.employerMonthlyAmount != nil { number(L10n.text("ui.monthly_employer_amount.ce3acb62"), value: Binding(get: { rule.employerMonthlyAmount ?? 0 }, set: { rule.employerMonthlyAmount = $0 })) }
                number(L10n.text("ui.annual_floor.9fbffe42"), value: $rule.floor)
                number(L10n.text("ui.annual_cap_0_none.c8d87741"), value: Binding(get: { rule.ceiling ?? 0 }, set: { rule.ceiling = $0 > 0 ? $0 : nil }))
                percent(L10n.text("ui.deductible_share.cb69e1b9"), value: $rule.deductibleShare)
                Button(L10n.text("ui.remove.c3812fc4"), systemImage: "trash", role: .destructive) { policy.contributions.removeAll { $0.id == rule.id } }
                    .labelStyle(.iconOnly).help(L10n.text("ui.remove.c3812fc4"))
            }
        }
        ForEach(policy.parameters.keys.sorted(), id: \.self) { key in
            number(key, value: Binding(get: { policy.parameters[key] ?? 0 }, set: { policy.parameters[key] = $0 }))
        }
    }
    private func bands(_ items: Binding<[TaxBand]>, title: String) -> some View {
        DisclosureGroup {
            ForEach(items.wrappedValue.indices, id: \.self) { index in
                HStack {
                    number(L10n.text("ui.lower_threshold.bb112f3f"), value: items[index].lower)
                    percent(L10n.text("ui.rate.2fe0599d"), value: items[index].rate)
                    Button(L10n.text("ui.remove.c3812fc4"), systemImage: "trash", role: .destructive) { items.wrappedValue.remove(at: index) }
                        .labelStyle(.iconOnly).help(L10n.text("ui.remove.c3812fc4"))
                }
            }
        } label: {
            HStack {
                Text(L10n.text(title))
                Spacer()
                Button(L10n.text("ui.add_band.4375e3c6"), systemImage: "plus") {
                    items.wrappedValue.append(TaxBand(lower: (items.wrappedValue.last?.lower ?? 0) + 10_000, rate: 0))
                }.labelStyle(.iconOnly).help(L10n.text("ui.add_band.4375e3c6"))
            }
        }
    }
    private func percent(_ title: String, value: Binding<Double>) -> some View {
        number(title, value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }))
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent {
            TextField("0", value: value, format: .number.grouping(.never).precision(.fractionLength(0 ... 2)))
                .labelsHidden().accessibilityLabel(L10n.text(title))
                .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 155)
        } label: { text(title) }
    }
    private func apply() {
        do {
            guard model.access.settingsUnlocked && !model.privacy.isPrivacyModeEnabled else { return }
            if region == .china { china.currency = .cny; try DayPerkModel.validate(china, requiresChinaPayroll: true) }
            try model.saveRegionalSettings(region: region, input: input, policy: policy, timeZoneID: timeZone)
            if region == .china {
                var updated = model.configuration
                updated.baseSalary = china.baseSalary; updated.payroll = china.payroll; updated.currency = .cny
                try model.saveConfiguration(updated)
            }
            onApply()
            message = L10n.text("ui.configuration_applied.e8381698"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
}
