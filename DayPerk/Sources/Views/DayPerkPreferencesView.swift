import SwiftUI

enum PreferencePage: String, CaseIterable, Identifiable {
    case salary = "payroll.settings", today = "correction.title", history = "历史补录", work = "schedule.title", linking = "linking.title", workStatus = "workstatus.title", statistics = "收入与工时统计", display = "settings.language_display_theme", data = "backup.title"
    var id: String {
        rawValue
    }

    var containsSalaryData: Bool {
        self == .salary || self == .today || self == .history || self == .statistics || self == .data
    }

    var requiresWholePageUnlock: Bool {
        self == .history
    }

    var icon: String {
        switch self { case .workStatus: return "tag"; case .data: return "externaldrive"; case .statistics: return "chart.bar"; case .today: return "clock.arrow.circlepath"; case .salary: return "banknote"; case .history: return "calendar.badge.plus"; case .work: return "calendar"; case .linking: return "cup.and.saucer"; case .display: return "menubar.rectangle" }
    }
}

private struct ConfigurationDraft {
    var config: DayPerkConfiguration
    var values: [String: String]
    private(set) var numberLocale: Locale
    init(_ c: DayPerkConfiguration, locale: Locale = LocalizationManager.shared.currentLocale) {
        numberLocale = locale
        config = c
        let p = c.payroll.policy
        let pairs: [(String, Double)] = [
            ("salary", c.baseSalary), ("allowance", c.housingAllowance), ("days", Double(c.workdaysPerMonth)), ("breakHours", Double(c.dailyBreakMinutes) / 60),
            ("socialBase", c.payroll.contributionBase), ("fundBase", c.payroll.housingFundBase),
            ("fundRate", c.payroll.housingFundRate * 100), ("employerFundRate", p.employerHousingFundRate * 100),
            ("pension", p.pensionRate * 100), ("medical", p.medicalRate * 100), ("unemployment", p.unemploymentRate * 100),
            ("socialMin", p.socialBaseMinimum), ("socialMax", p.socialBaseMaximum),
            ("fundMin", p.housingBaseMinimum), ("fundMax", p.housingBaseMaximum),
            ("additional", c.payroll.monthlySpecialAdditionalDeduction), ("bonusBase", c.payroll.annualBonusBase),
            ("bonusMonths", c.payroll.annualBonusMonths), ("year", Double(c.payroll.taxYear)),
            ("month", Double(c.payroll.taxMonth)), ("startMonth", Double(c.payroll.employmentStartMonth)),
            ("startYear", Double(c.payroll.employmentStartYear ?? c.payroll.taxYear)),
            ("overtime", c.overtimeMultiplier),
            ("medicalFixed", p.personalMedicalFixed ?? 0),
            ("fundSupplemental", (p.supplementaryFundRate ?? 0) * 100),
            ("employerFundSupplemental", (p.employerSupplementaryFundRate ?? 0) * 100),
        ]
        values = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 2)))) })
        for (key, value) in [("medicalMin", p.medicalBaseMinimum), ("medicalMax", p.medicalBaseMaximum), ("unemploymentMin", p.unemploymentBaseMinimum), ("unemploymentMax", p.unemploymentBaseMaximum)] {
            values[key] = value.map { $0.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 2))) } ?? ""
        }
        let employerDefaults = CityPayrollTemplates.all.first { $0.id == (p.cityTemplateID ?? "hangzhou") }?.values ?? [:]
        for (key, value) in [("employerPension", p.employerPensionRate), ("employerMedical", p.employerMedicalRate), ("employerUnemployment", p.employerUnemploymentRate), ("employerMaternity", p.employerMaternityRate), ("employerInjury", p.employerInjuryRate)] {
            values[key] = (value ?? employerDefaults[key].map { $0 / 100 }).map { ($0 * 100).formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 2))) } ?? ""
        }
    }

    mutating func updateLocale(_ locale: Locale) {
        for (key, text) in values {
            if let value = LocalizedNumberInput.value(text, locale: numberLocale) {
                values[key] = value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0 ... 2)))
            }
        }
        numberLocale = locale
    }

    func number(_ key: String) throws -> Double {
        guard let value = LocalizedNumberInput.value(values[key] ?? "", locale: numberLocale) else {
            throw DayPerkInputError(message: L10n.text("ui.enter_a_complete_number_without_cur.9f19b108"))
        }
        return value
    }

    func integer(_ key: String) throws -> Int {
        let n = try number(key)
        guard n >= 0, n <= 10000, n.rounded() == n else { throw DayPerkInputError(message: L10n.text("ui.years_months_and_workday_counts_mus.f854efc6")) }
        return Int(n)
    }

    func optionalNumber(_ key: String) throws -> Double? {
        if (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return try number(key)
    }

    func validatedConfiguration() throws -> DayPerkConfiguration {
        var c = config
        c.baseSalary = try number("salary"); c.housingAllowance = try number("allowance")
        c.workdaysPerMonth = try integer("days"); c.overtimeMultiplier = try number("overtime")
        c.payroll.contributionBase = try number("socialBase"); c.payroll.housingFundBase = try number("fundBase")
        c.payroll.housingFundRate = try number("fundRate") / 100
        c.payroll.monthlySpecialAdditionalDeduction = try number("additional")
        c.payroll.annualBonusBase = try number("bonusBase"); c.payroll.annualBonusMonths = try number("bonusMonths")
        if c.breakMode == .totalHours {
            let breakHours = try number("breakHours")
            guard breakHours >= 0, breakHours < 24 else { throw DayPerkInputError(message: L10n.text("ui.daily_reference_break_must_be_less.779b5bd7")) }
            c.dailyBreakMinutes = Int((breakHours * 60).rounded())
        }
        c.payroll.taxYear = try integer("year"); c.payroll.taxMonth = try integer("month")
        c.payroll.employmentStartMonth = try integer("startMonth")
        c.payroll.employmentStartYear = try integer("startYear")
        c.payroll.policy.pensionRate = try number("pension") / 100
        c.payroll.policy.medicalRate = try number("medical") / 100
        c.payroll.policy.unemploymentRate = try number("unemployment") / 100
        c.payroll.policy.employerHousingFundRate = try number("employerFundRate") / 100
        c.payroll.policy.socialBaseMinimum = try number("socialMin"); c.payroll.policy.socialBaseMaximum = try number("socialMax")
        c.payroll.policy.housingBaseMinimum = try number("fundMin"); c.payroll.policy.housingBaseMaximum = try number("fundMax")
        c.payroll.policy.personalMedicalFixed = try number("medicalFixed")
        c.payroll.policy.supplementaryFundRate = try number("fundSupplemental") / 100
        c.payroll.policy.employerSupplementaryFundRate = try number("employerFundSupplemental") / 100
        c.payroll.policy.medicalBaseMinimum = try optionalNumber("medicalMin")
        c.payroll.policy.medicalBaseMaximum = try optionalNumber("medicalMax")
        c.payroll.policy.unemploymentBaseMinimum = try optionalNumber("unemploymentMin")
        c.payroll.policy.unemploymentBaseMaximum = try optionalNumber("unemploymentMax")
        c.payroll.policy.employerPensionRate = try optionalNumber("employerPension").map { $0 / 100 }
        c.payroll.policy.employerMedicalRate = try optionalNumber("employerMedical").map { $0 / 100 }
        c.payroll.policy.employerUnemploymentRate = try optionalNumber("employerUnemployment").map { $0 / 100 }
        c.payroll.policy.employerMaternityRate = try optionalNumber("employerMaternity").map { $0 / 100 }
        c.payroll.policy.employerInjuryRate = try optionalNumber("employerInjury").map { $0 / 100 }
        return c
    }
}

struct DayPerkPreferencesView: View {
    @ObservedObject private var access: SalaryAccessController
    @ObservedObject var model: DayPerkModel
    @ObservedObject private var language = LocalizationManager.shared
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var selectedTemplate = "hangzhou"
    @State private var page: PreferencePage = .salary
    @State private var payRegion: PayrollRegion
    @State private var payTimeZone: String
    @State private var draft: ConfigurationDraft
    @State private var message = ""
    @State private var isError = false
    @State private var editingRecord: PayrollIncomeRecord?
    @State private var leaveDraft = LeaveRequestDraft()
    @State private var overrideDate = Date()
    @State private var overrideKind = DayArrangement.automatic
    @State private var overrideMultiplier = "2"

    init(model: DayPerkModel, initialPage: PreferencePage = .salary) {
        self.model = model
        _access = ObservedObject(wrappedValue: model.access)
        _selectedTemplate = State(initialValue: model.payroll.policy.cityTemplateID ?? "hangzhou")
        _page = State(initialValue: initialPage)
        _payRegion = State(initialValue: model.regional.region)
        _payTimeZone = State(initialValue: model.regional.timeZoneID)
        _draft = State(initialValue: ConfigurationDraft(model.configuration))
    }

    var body: some View {
        Group {
            if access.isDataLocked {
                SalaryUnlockView(access: access, controls: model)
                    .frame(minWidth: 900, minHeight: 660)
            } else {
                preferencesContent
            }
        // 刷新现有窗口里的全部译文，外层待保存配置仍保留。
        }.id(language.effectiveLanguageCode).preferredColorScheme(.dark).tint(appearance.theme.color).environment(\.locale, language.currentLocale).environment(\.timeZone, model.workCalendar.timeZone)
            .buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle())
            .onChange(of: language.currentLanguage) { _, _ in
                if let multiplier = LocalizedNumberInput.value(overrideMultiplier, locale: draft.numberLocale) {
                    overrideMultiplier = multiplier.formatted(.number.locale(language.currentLocale).grouping(.never))
                }
                draft.updateLocale(language.currentLocale)
            }
            .scrollContentBackground(.hidden)
            .background(BrewBackground(appearance: appearance))
            .actionFeedback($message, isError: isError).actionToastHost()
            .onChange(of: access.authenticationMessage) { _, text in ActionToastCenter.shared.show(text, isError: true) }
            .onChange(of: access.isDataLocked) { _, _ in ActionToastCenter.shared.dismiss() }
            .onDisappear { ActionToastCenter.shared.dismiss() }
            .onChange(of: payRegion) { _, value in
                if value == .china { payTimeZone = "Asia/Shanghai" }
            }
    }

    private var preferencesContent: some View {
        HStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("ui.dayperk.5a2918b6"), systemImage: "cup.and.saucer.fill").font(.title2.weight(.semibold)).padding(.horizontal, 16)
                ForEach([PreferencePage.salary, .today, .history, .work, .linking, .workStatus, .statistics, .display, .data]) { item in
                    Button { page = item; message = "" } label: {
                        Label(L10n.text(item.rawValue), systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(page == item ? appearance.theme.color.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(16).padding(.top, 20)
            }.frame(width: 190).background(appearance.theme.sidebar.opacity(appearance.background.enabled ? 0.65 : 0.92))
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Text(L10n.text(page.rawValue)).font(.title2.weight(.semibold)).foregroundStyle(appearance.theme.color)
                        InfoHelp(text: page == .workStatus ? L10n.text("workstatus.help") : page == .data ? L10n.text("backup.help") : page == .statistics ? L10n.text("ui.totals_use_daily_records_authentica.9faba690") : page == .history ? L10n.text("ui.actual_income_records_inform_later.d404d24c") : page == .display ? L10n.text("ui.theme_background_language_and_preci.32d32254") : L10n.text("ui.save_to_validate_and_apply_changes.a8fac781")).frame(width: 18, height: 18)
                    }
                    Spacer()
                    if page == .display {
                        Button(L10n.text("display.reset"), systemImage: "arrow.counterclockwise") {
                            model.resetDisplaySettings { error in
                                if let error { message = error.localizedDescription; isError = true }
                                else { draft.config.currency = model.currency.currentCurrency; message = L10n.text("display.reset_done"); isError = false }
                            }
                        }.labelStyle(.iconOnly).help(L10n.text("display.reset_help"))
                    }
                    if page == .statistics {
                        ShowcaseModeButton(model: model)
                    }
                    if page.containsSalaryData {
                        Button {
                            if access.settingsUnlocked { access.revokeAuthorization() } else { access.unlockSettings() }
                        } label: {
                            Image(systemName: access.settingsUnlocked ? "lock.open.fill" : "lock.fill").frame(width: 16, height: 16)
                        }.accessibilityLabel(L10n.text(access.settingsUnlocked ? "ui.revoke_all_access.47d109d6" : "ui.unlock_salary_data.76ac2b3c"))
                            .accessibilityValue(L10n.text(access.settingsUnlocked ? "report.unlocked" : "report.locked"))
                            .help(L10n.text(access.settingsUnlocked ? "ui.revoke_all_access.47d109d6" : "ui.unlock_salary_data.76ac2b3c"))
                            .disabled(access.isAuthenticating)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 14)
                Divider()
                Group {
                    if page.requiresWholePageUnlock && !access.settingsUnlocked {
                        SalaryUnlockView(access: access, settings: true)
                    } else {
                        switch page {
                        case .salary: if payRegion == .china { AnyView(salaryForm) } else { AnyView(RegionalPayrollView(model: model, initialRegion: payRegion, onRegionChange: { payRegion = $0 }) { draft = ConfigurationDraft(model.configuration); payTimeZone = model.regional.timeZoneID }) }
                                                case .today: WorkDataCorrectionView(model: model)
                        case .history: if model.usesChinaPayroll { AnyView(historyForm) } else { AnyView(RegionalIncomeHistoryView(model: model)) }
                        case .work: workForm
                        case .linking: WorkLinkingView(config: $draft.config)
                        case .workStatus: WorkStatusSettingsView(controller: model.workStatus)
                        case .statistics: WorkStatisticsView(model: model)
                        case .data: DataTransferView(model: model)
                        case .display: displayForm
                        }
                    }
                }.frame(maxWidth: 1000, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsSaveFooter {
                Divider()
                HStack {
                    Spacer()
                    if page != .data && page != .history && page != .today && page != .statistics && !(page == .salary && payRegion != .china) && (!page.requiresWholePageUnlock || access.settingsUnlocked) {
                        Button(L10n.text("ui.discard_changes.93eab398")) { draft = ConfigurationDraft(model.configuration); payRegion = model.regional.region; payTimeZone = model.regional.timeZoneID; message = L10n.text("ui.saved_settings_restored.b295a47e"); isError = false }
                        Button(L10n.text("ui.save_settings.6e584e3d"), systemImage: "checkmark", action: save).buttonStyle(BrewButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command).disabled(page == .salary && (!access.settingsUnlocked || model.privacy.isPrivacyModeEnabled))
                    }
                }.padding(14)
                }
            }
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 740, idealHeight: 820)
        .preferredColorScheme(.dark).tint(appearance.theme.color)
        .environment(\.locale, language.currentLocale).environment(\.timeZone, model.workCalendar.timeZone)
        .background(InputFocusDismissal())
        .onChange(of: access.settingsUnlocked) { _, unlocked in
            if !unlocked {
                editingRecord = nil; HoverHelpButton.closeActive()
            }
        }
        .onChange(of: model.privacy.isPrivacyModeEnabled) { _, hidden in
            if hidden {
                NSApp.keyWindow?.makeFirstResponder(nil)
                HoverHelpButton.closeActive()
            }
        }
        .onChange(of: model.regional.selectedPolicy.id) { _, _ in draft = ConfigurationDraft(model.configuration) }
        .onChange(of: model.payroll.includeAnnualBonus) { _, value in draft.config.payroll.includeAnnualBonus = value }
        .onChange(of: model.payroll.isEnabled) { _, value in draft.config.payroll.isEnabled = value }
        .onChange(of: model.includeHousingFundInRate) { _, value in draft.config.includeHousingFundInRate = value }
        .onChange(of: model.includeHousingFundInEstimate) { _, value in draft.config.includeHousingFundInEstimate = value }
        .onChange(of: draft.config.rhythm.scheduleRules) { _, rules in
            var candidate = model.rhythm; candidate.scheduleRules = rules
            guard (try? candidate.validate()) != nil else { return }
            do { try model.saveScheduleRules(rules) }
            catch { message = error.localizedDescription; isError = true }
        }
        .onChange(of: overrideDate) { _, _ in loadDateArrangement() }
        .onChange(of: model.configuration.dateOverrides) { _, value in draft.config.dateOverrides = value; loadDateArrangement() }
        .onChange(of: model.overtimeDates) { _, value in draft.config.overtimeDates = value; loadDateArrangement() }
        .onAppear { loadDateArrangement() }
        .sheet(item: $editingRecord) { record in PayrollRecordEditor(model: model, record: record).background(InputFocusDismissal()) }
    }

    private var showsSaveFooter: Bool {
        page != .data && page != .history && page != .today && page != .statistics && page != .workStatus
            && !(page == .salary && payRegion != .china) && (!page.requiresWholePageUnlock || access.settingsUnlocked)
    }

    private func breakTime(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(get: { Date.createTime(hour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60) }, set: {
            minute.wrappedValue = model.workCalendar.component(.hour, from: $0) * 60 + model.workCalendar.component(.minute, from: $0)
        })
    }

    private func cityPreview(_ template: CityPayrollTemplate) -> some View { ChinaContributionPreview(template: template) }

    var paydaySection: some View {
        Section(L10n.text("ui.pay_schedule.40744a36")) {
                Picker(L10n.text("ui.payday.4f151a17"), selection: $draft.config.payday.usesLastDay) {
                    Text(L10n.text("ui.fixed_day_of_month.8c3da631")).tag(false)
                    Text(L10n.text("ui.last_day_of_month.9de7e7f4")).tag(true)
                }.pickerStyle(.segmented)
                if !draft.config.payday.usesLastDay {
                    Picker(L10n.text("ui.day_of_month.992d6e34"), selection: $draft.config.payday.day) {
                        ForEach(1 ... 31, id: \.self) { day in Text("\(day)").tag(day) }
                    }
                }
                option(L10n.text("ui.pay_on_previous_workday_if_due_on_a.7024516c"), value: $draft.config.payday.advanceOnRestDay,
                       help: L10n.text("ui.uses_holidays_makeup_workdays_and_c.fa68de76"))
                LabeledContent(L10n.text("ui.estimated_payday_this_month.cb8d3f59"), value: draftPayday)
            }
    }

    private var salaryForm: some View {
        Form {
            Section {
                Picker(L10n.text("ui.payroll_region.6e425cd7"), selection: $payRegion) {
                    ForEach(PayrollRegion.allCases) { Text(L10n.text($0.name)).tag($0) }
                }
                HStack {
                    Text(L10n.text("ui.work_time_zone.150fd218"))
                    InfoHelp(text: WorkTimeZoneOptions.explanation).frame(width: 18, height: 18)
                    Spacer()
                    WorkTimeZonePicker(identifier: $payTimeZone, preferredCity: "Asia/Shanghai")
                }
            }
            Section(L10n.text("ui.city_contribution_presets.24e8ec2f")) {
                if let template = CityPayrollTemplates.all.first(where: { $0.id == selectedTemplate }) {
                    HStack(spacing: 10) {
                        Text(L10n.text("ui.city.317f75c9"))
                        InfoHelp(text: L10n.text("ui.selecting_a_city_previews_its_defau.b30264ba") + "\n" + L10n.text(template.note))
                            .frame(width: 18, height: 18)
                        Spacer()
                        Picker(L10n.text("ui.city.317f75c9"), selection: $selectedTemplate) {
                            ForEach(CityPayrollTemplates.all) { city in Text(L10n.text(city.name)).tag(city.id) }
                        }.labelsHidden().frame(width: 130)
                        Button(L10n.text("ui.apply_preset.1278b8f6")) {
                            guard access.settingsUnlocked else { access.unlockSettings(); return }
                            do {
                                let c = try template.applying(to: draft.validatedConfiguration())
                                try applyChinaConfiguration(c)
                                draft = ConfigurationDraft(model.configuration)
                                message = L10n.format("ui.1.89855e09", String(describing: template.name)); isError = false
                            } catch { message = error.localizedDescription; isError = true }
                        }.buttonStyle(BrewButtonStyle(prominent: true))
                    }
                    cityPreview(template)
                    ChinaTaxDisclosure(template: template)
                }
            }
            paydaySection
            Section(L10n.text("ui.earnings_basis.457f059d")) {
                option(L10n.text("ui.include_annual_bonus.cd52e941"), value: $draft.config.payroll.includeAnnualBonus,
                       help: L10n.text("ui.spread_the_expected_annual_bonus_ac.696bf43e"))
                option(L10n.text("ui.deduct_tax_employee_contributions.c2f5bdc5"), value: $draft.config.payroll.isEnabled,
                       help: L10n.text("ui.deduct_salary_tax_employee_social_i.d609519d"))
                helpRow(L10n.text("ui.recalculate_earnings_from_tracked_t.79a7d4af"), help: L10n.text("ui.pay_changes_recalculate_today_from.28108f7e"))
            }
            if !access.settingsUnlocked {
                Section(L10n.text("ui.personal_pay_data.ba469687")) { SalaryUnlockView(access: access, settings: true).frame(height: 210) }
            } else {
                Section(L10n.text("ui.monthly_income.153c8e06")) {
                    input(L10n.text("ui.base_salary.91910663"), key: "salary", unit: L10n.text("ui.cny_month.81667177"))
                    input(L10n.text("ui.housing_fixed_allowances.97e613b5"), key: "allowance", unit: L10n.text("ui.cny_month.81667177"))
                    helpRow(L10n.text("ui.how_is_monthly_income_calculated.e9f91a65"), help: L10n.text("ui.gross_monthly_income_is_base_salary.402a8bcb"))
                }
                annualBonusSection
                WithdrawableBenefitsSection(model: model, region: .china, currency: model.activeCurrencyCode)
                    .id(model.activeCurrencyCode)
                Section(L10n.text("ui.employee_social_insurance.e10217d3")) {
                    input(L10n.text("ui.social_insurance_contribution_base.b537e541"), key: "socialBase", unit: L10n.text("ui.cny.7f77f23a"))
                    input(L10n.text("ui.employee_pension_rate.a5b27045"), key: "pension", unit: "%")
                    input(L10n.text("ui.employee_medical_rate.3f7b1d72"), key: "medical", unit: "%")
                    input(L10n.text("ui.employee_unemployment_rate.e10269ae"), key: "unemployment", unit: "%")
                    input(L10n.text("ui.fixed_monthly_employee_medical_fee.afcc33ba"), key: "medicalFixed", unit: L10n.text("ui.cny.7f77f23a"))
                    DisclosureGroup(L10n.text("ui.contribution_base_ranges.94a8d7c9")) {
                        input(L10n.text("ui.minimum_social_insurance_base.888ad291"), key: "socialMin", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.maximum_social_insurance_base.318aab11"), key: "socialMax", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.minimum_housing_fund_base.3461d838"), key: "fundMin", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.maximum_housing_fund_base.81f611a3"), key: "fundMax", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.minimum_medical_base_optional.235bf1b0"), key: "medicalMin", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.maximum_medical_base_optional.c4f53a0f"), key: "medicalMax", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.minimum_unemployment_base_optional.3ad44c51"), key: "unemploymentMin", unit: L10n.text("ui.cny.7f77f23a"))
                        input(L10n.text("ui.maximum_unemployment_base_optional.9e1ac6bb"), key: "unemploymentMax", unit: L10n.text("ui.cny.7f77f23a"))
                    }
                }
                Section(L10n.text("ui.employer_social_insurance_not_deduc.5b84a37e")) {
                    input(L10n.text("ui.employer_pension_rate.4fc34ba2"), key: "employerPension", unit: "%")
                    input(L10n.text("ui.employer_medical_rate.d51883c2"), key: "employerMedical", unit: "%")
                    input(L10n.text("ui.employer_unemployment_rate.573b30eb"), key: "employerUnemployment", unit: "%")
                    input(draft.config.payroll.policy.medicalIncludesMaternity == true ? L10n.text("ui.maternity_rate_included_in_medical.79dad6b6") : L10n.text("ui.employer_maternity_rate.4e8b024e"), key: "employerMaternity", unit: "%")
                    input(L10n.text("ui.employer_work_injury_rate.2cf9d496"), key: "employerInjury", unit: "%")
                    helpRow(L10n.text("ui.about_employer_rates.8b284cdc"), help: L10n.text("ui.employer_contributions_are_not_dedu.97374f66"))
                }
                Section(L10n.text("ui.housing_fund.397c8572")) {
                    input(L10n.text("ui.housing_fund_contribution_base.662ad43b"), key: "fundBase", unit: L10n.text("ui.cny.7f77f23a"))
                    input(L10n.text("ui.employee_contribution_rate.a58abf26"), key: "fundRate", unit: "%")
                    input(L10n.text("ui.employer_contribution_rate.86245aab"), key: "employerFundRate", unit: "%")
                    input(L10n.text("ui.employee_supplementary_fund_rate.d6f20da0"), key: "fundSupplemental", unit: "%")
                    input(L10n.text("ui.employer_supplementary_fund_rate.8e4f685d"), key: "employerFundSupplemental", unit: "%")
                    helpRow(L10n.text("ui.how_is_the_housing_fund_calculated.fb9c7a6d"), help: L10n.text("ui.calculate_employee_and_employer_con.1f4c937a"))
                }
                Section(L10n.text("ui.cumulative_tax_withholding.74218954")) {
                    input(L10n.text("ui.monthly_additional_deductions.d50efaaa"), key: "additional", unit: L10n.text("ui.cny.7f77f23a"))
                    input(L10n.text("ui.employment_tax_start_year.5ea6a9a7"), key: "startYear", unit: L10n.text("ui.year.62ef900a"))
                    input(L10n.text("ui.employment_tax_start_month.8688eeee"), key: "startMonth", unit: L10n.text("ui.1_12.f2bbe386"))
                    Toggle(L10n.text("ui.follow_current_year_month.7abf4e9f"), isOn: $draft.config.followsCurrentMonth)
                    input(L10n.text("ui.tax_year.b3501a38"), key: "year", unit: L10n.text("ui.year.62ef900a")).disabled(draft.config.followsCurrentMonth)
                    input(L10n.text("ui.tax_month.7b6528e4"), key: "month", unit: L10n.text("ui.1_12.f2bbe386")).disabled(draft.config.followsCurrentMonth)
                    helpRow(L10n.text("ui.which_deductions_can_i_enter.13e731fd"), help: L10n.text("ui.enter_eligible_rent_mortgage_educat.f08b9f10"))
                }
            }
        }.formStyle(.grouped)
    }

    private var bonusPreview: PayrollDeductionConfiguration {
        var c = draft.config.payroll
        c.annualBonusBase = LocalizedNumberInput.value(draft.values["bonusBase"] ?? "", locale: draft.numberLocale) ?? 0
        c.annualBonusMonths = LocalizedNumberInput.value(draft.values["bonusMonths"] ?? "", locale: draft.numberLocale) ?? 0
        c.taxYear = draft.config.followsCurrentMonth ? model.payroll.configuration.taxYear : (Int(draft.values["year"] ?? "") ?? c.taxYear)
        return c
    }

    var annualBonusSection: some View {
        let c = bonusPreview
        let factor = PayrollCalculator.annualBonusProrationFactor(for: c)
        let bonus = PayrollCalculator.annualBonusGross(for: c)
        let tax = PayrollCalculator.annualBonusTax(for: bonus)
        func amount(_ value: Double) -> String {
            model.privacy.isPrivacyModeEnabled ? "•••" : model.currency.formatAmount(value, currencyCode: "CNY")
        }
        return Section(L10n.text("ui.annual_bonus.2cbdbdcd")) {
            input(L10n.text("ui.bonus_salary_base_excluding_allowan.242f88eb"), key: "bonusBase", unit: L10n.text("ui.cny.7f77f23a"))
            input(L10n.text("ui.full_year_bonus_months.0a77d19e"), key: "bonusMonths", unit: L10n.text("ui.months.e5afd16c"))
            option(L10n.text("ui.prorate_bonus_by_hire_date.0af4c900"), value: $draft.config.payroll.prorateAnnualBonus,
                   help: L10n.text("ui.full_year_bonus_remaining_full_mont.aee7d486"))
            if c.prorateAnnualBonus {
                HStack {
                    Text(L10n.text("ui.hire_date_for_bonus_proration.d19e73cb"))
                    Spacer()
                    BrewDatePicker(title: L10n.text("ui.hire_date_for_bonus_proration.d19e73cb"), selection: $draft.config.payroll.annualBonusStartDate, calendar: model.workCalendar)
                        .labelsHidden().datePickerStyle(.field).fixedSize()
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                }
                LabeledContent(L10n.text("ui.proration_factor.7abe80c0"), value: model.privacy.isPrivacyModeEnabled ? "•••" : factor.formatted(.percent.locale(language.currentLocale).precision(.fractionLength(2))))
                LabeledContent(L10n.text("ui.prorated_bonus_months.1735f7b8"), value: model.privacy.isPrivacyModeEnabled ? "•••" : (max(0, c.annualBonusMonths) * factor).formatted(.number.locale(language.currentLocale).precision(.fractionLength(4))))
            }
            LabeledContent(L10n.text("ui.bonus_year.3fb39d7f"), value: String(c.taxYear))
            LabeledContent(L10n.text("ui.estimated_gross_bonus.c867693a"), value: amount(bonus)).monospacedDigit()
            if c.taxYear <= 2027 {
                LabeledContent(L10n.text("ui.estimated_bonus_tax.e334090f"), value: amount(tax)).monospacedDigit()
                LabeledContent(L10n.text("ui.estimated_net_bonus.8c692d8b"), value: amount(bonus - tax))
                    .monospacedDigit().foregroundStyle(appearance.theme.color)
            }
            helpRow(L10n.text("ui.how_is_the_bonus_included_in_time_v.d4749db3"), help: L10n.text("ui.the_preview_updates_as_you_type_sav.392e6844"))
        }
    }

    private var draftCalendarPlan: WorkPlan {
        let overrides = model.usesChinaPayroll || draft.config.rhythm.observesPublicHolidays == false ? draft.config.dateOverrides
            : RegionalHolidayCalendar.shared.overrides(country: model.regional.region.rawValue, subdivision: model.regional.selectedPolicy.subdivision, manual: draft.config.dateOverrides)
        return WorkPlan(weekdays: Set(draft.config.weekdays.map { $0.calendarWeekday }), dateOverrides: overrides, dayStartMinute: draft.config.dayStartMinute, rhythm: draft.config.rhythm)
    }

    private var draftMonth: DateComponents {
        model.workCalendar.dateComponents([.year, .month], from: draftCalendarPlan.businessDayStart(for: Date(), calendar: model.workCalendar))
    }

    private var draftWorkdays: Int {
        draftCalendarPlan.regularWorkdays(year: draftMonth.year!, month: draftMonth.month!, calendar: model.workCalendar)
    }

    private var draftPayday: String {
        guard let date = draft.config.payday.date(year: draftMonth.year!, month: draftMonth.month!, plan: draftCalendarPlan, calendar: model.workCalendar) else { return "—" }
        return L10n.payday(date, calendar: model.workCalendar)
    }

    private var workForm: some View {
        Form {
            Section {
                HolidayCalendarView(overrides: Binding(get: { draft.config.dateOverrides }, set: {
                    draft.config.dateOverrides = $0; model.updateWorkdayOverrides($0)
                }), selectedDate: Binding(get: { leaveDraft.isSelecting ? leaveDraft.selection.start : overrideDate }, set: { if leaveDraft.isSelecting { leaveDraft.selection.start = $0 } else { leaveDraft.base.start = $0 }; overrideDate = $0 }),
                    overtimeDates: draft.config.overtimeDates, region: model.regional.region,
                    subdivision: model.regional.selectedPolicy.subdivision, rhythm: draft.config.rhythm,
                    weekdays: Set(draft.config.weekdays.map(\.calendarWeekday)), workCalendar: model.workCalendar,
                    leaveDays: model.leaveDays, selectionEnd: leaveDraft.isSelecting ? $leaveDraft.selection.end : nil,
                    confirmedRange: leaveDraft.isSelecting ? leaveDraft.confirmedBase.map { $0.start ... $0.end } : nil,
                    selectionBounds: leaveDraft.isSelecting ? leaveDraft.selectionBounds : nil, selectionID: leaveDraft.isSelecting ? leaveDraft.selectedSegmentID : nil)
            } header: {
                HStack {
                    Text(L10n.text("schedule.calendar"))
                    InfoHelp(text: L10n.text("leave.calendar_help")).frame(width: 18, height: 18)
                    Spacer()
                    Button(L10n.text(leaveDraft.isSelecting ? (leaveDraft.confirmedBase == nil ? "leave.cancel_selection" : "leave.finish_adjustments") : "leave.begin")) {
                        if leaveDraft.isSelecting {
                            do { if leaveDraft.confirmedBase != nil { try model.saveLeaveRequest(&leaveDraft, finish: true) } else { leaveDraft.isSelecting = false } }
                            catch { message = error.localizedDescription; isError = true }
                        }
                        else { leaveDraft.beginSelection() }
                    }.buttonStyle(BrewButtonStyle(prominent: leaveDraft.isSelecting))
                }
            }
            if !leaveDraft.isSelecting { dayArrangementSection }
            LeaveEditorSections(model: model, draft: $leaveDraft)
            Section(L10n.text("ui.day_boundary.cee973d7")) {
                DatePicker(L10n.text("ui.day_starts_at.5d2e5da4"), selection: breakTime($draft.config.dayStartMinute), displayedComponents: .hourAndMinute).datePickerStyle(.field)
                helpRow(L10n.text("ui.tracking_across_days.d4f01701"), help: L10n.text("ui.a_new_day_starts_at_04_00_by_defaul.ecd80cc0"))
            }
            Section(L10n.text("ui.reference_schedule_earnings_rate.d067ffc0")) {
                ScheduleTimeRange(startTitle: "ui.work_starts.8a53fbd1", endTitle: "ui.work_ends.6d4cffbc", start: $draft.config.startTime, end: $draft.config.endTime)
                Picker(L10n.text("ui.break_mode.0cbad458"), selection: $draft.config.breakMode) {
                    ForEach(WorkBreakMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented)
                if draft.config.breakMode == .totalHours {
                    input(L10n.text("ui.daily_reference_break.8e206a2b"), key: "breakHours", unit: L10n.text("ui.hours.3b6fefc5"), help: L10n.text("ui.a_total_break_duration_affects_the.d22ff989"))
                } else {
                    HStack {
                        helpRow(L10n.text("ui.exclude_break_periods.570bd524"), help: L10n.text("ui.subtract_these_periods_from_the_ref.0764cb00"))
                        Spacer()
                        Button(L10n.text("ui.add_break_period.02ecdb1d"), systemImage: "plus") {
                            let c = model.workCalendar
                            let start = c.component(.hour, from: draft.config.startTime) * 60 + c.component(.minute, from: draft.config.startTime)
                            draft.config.breakPeriods.append(WorkBreak(startMinute: start, endMinute: (start + 30) % 1440))
                        }.labelStyle(.iconOnly).help(L10n.text("ui.add_break_period.02ecdb1d"))
                    }
                    ForEach($draft.config.breakPeriods) { $period in
                        HStack {
                            ScheduleTimeRange(startTitle: "ui.break_starts.65d83a76", endTitle: "ui.break_ends.91dcd170", start: breakTime($period.startMinute), end: breakTime($period.endMinute))
                            Button(L10n.text("ui.remove.6135d415"), systemImage: "trash", role: .destructive) { draft.config.breakPeriods.removeAll { $0.id == period.id } }
                                .labelStyle(.iconOnly).help(L10n.text("ui.remove.6135d415"))
                        }
                    }
                }
                HStack {
                    Text(L10n.text("ui.workdays_this_month.d364b7f9"))
                    InfoHelp(text: L10n.text("ui.counts_this_month_s_regular_workday.f043ceeb")).frame(width: 18, height: 18)
                    Spacer()
                    Text("\(draftWorkdays)").monospacedDigit()
                    Text(L10n.text("ui.days.49da61ce")).foregroundStyle(.secondary)
                }
                input(L10n.text("ui.default_overtime_multiplier.1e83e128"), key: "overtime", unit: L10n.text("ui.message.16729fb4"), help: L10n.text("ui.selected_monthly_basis_divided_by_s.7a70cd1f"))
                WorkRhythmEditor(rhythm: $draft.config.rhythm, weekdays: $draft.config.weekdays, calendar: model.workCalendar, allowsHolidayOptOut: !model.usesChinaPayroll, fallback: draft.config.referenceSchedule)

            }
            WorkScheduleRulesEditor(rhythm: $draft.config.rhythm, fallback: draft.config.referenceSchedule, calendar: model.workCalendar)

        }.formStyle(.grouped)
    }

    private func loadDateArrangement() {
        let key = WorkPlan.dayKey(overrideDate, calendar: model.workCalendar)
        if let multiplier = model.overtimeDates[key] {
            overrideKind = .overtime
            overrideMultiplier = multiplier.formatted(.number.locale(language.currentLocale).grouping(.never))
        } else if let working = model.configuration.dateOverrides[key] {
            overrideKind = working ? .makeup : .rest
        } else { overrideKind = .automatic }
    }

    private var dayArrangementSection: some View {
        let key = WorkPlan.dayKey(overrideDate, calendar: model.workCalendar)
        let allowsMakeup = model.businessPlan.canMakeupWorkday(overrideDate, calendar: model.workCalendar)
            || (model.configuration.dateOverrides[key] == true && model.overtimeDates[key] == nil)
        return Section {
            LabeledContent(L10n.text("correction.selected_date"), value: overrideDate.formatted(.dateTime.year().month().day().locale(language.currentLocale)))
            HStack {
                Picker(L10n.text("ui.day_type.8646b42e"), selection: $overrideKind) {
                    ForEach(DayArrangement.allCases.filter { $0 != .makeup || allowsMakeup }) { kind in
                        Text(kind.title).tag(kind)
                    }
                }.pickerStyle(.segmented)
                Button(L10n.text("schedule.apply_day_arrangement"), systemImage: "checkmark") {
                    do {
                        let multiplier = LocalizedNumberInput.value(overrideMultiplier, locale: language.currentLocale) ?? 0
                        try model.applyDayArrangement(overrideKind, on: overrideDate, multiplier: multiplier)
                        draft.config.dateOverrides = model.configuration.dateOverrides
                        draft.config.overtimeDates = model.overtimeDates
                        message = L10n.text("schedule.day_arrangement_saved"); isError = false
                    } catch { message = error.localizedDescription; isError = true }
                }.labelStyle(.iconOnly).help(L10n.text("schedule.apply_day_arrangement"))
                    .buttonStyle(BrewButtonStyle(prominent: true))
            }
            if overrideKind == .overtime {
                HStack {
                    Text(L10n.text("ui.date_specific_overtime_multiplier.a6550a91")); Spacer()
                    TextField(L10n.text("ui.multiplier.205f1483"), text: $overrideMultiplier).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 150)
                    Text(L10n.text("ui.message.16729fb4"))
                }
            }
            DayScheduleEditor(rhythm: $draft.config.rhythm, day: WorkPlan.dayKey(overrideDate, calendar: model.workCalendar), fallback: draft.config.referenceSchedule, calendar: model.workCalendar)
        } header: {
            HStack {
                Text(L10n.text("ui.day_type.8646b42e"))
                InfoHelp(text: L10n.text("schedule.day_arrangement_help")).frame(width: 18, height: 18)
            }
        }
    }

    private var historyForm: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    Text(L10n.text("ui.how_income_history_is_used.5ea2cb1b")).foregroundStyle(.secondary)
                    InfoHelp(text: L10n.text("ui.current_salary_does_not_overwrite_a.dfc5794b")).frame(width: 18, height: 18)
                    Spacer()
                }
            }
            Section {
                if model.payroll.records.isEmpty {
                    Text(L10n.text("history.empty")).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(model.payroll.records.sorted { ($0.year, $0.month) > ($1.year, $1.month) }) { record in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: record.isSalary ? "banknote" : "doc.text").foregroundStyle(appearance.theme.color)
                            Text(L10n.format("ui.1_2_3.40e21d2f", String(record.year), String(record.month), L10n.text(record.isSalary ? "ui.salary.7f4e3a98" : "ui.service_income.bdced03d"))).font(.headline)
                            Spacer()
                            Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") { editingRecord = record }
                                .labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656"))
                        }
                        HStack(spacing: 16) {
                            historyMetric("history.gross", amount: record.income)
                            historyMetric("history.tax", amount: record.paidTax)
                            historyMetric("history.net", amount: max(0, record.income - record.paidTax - record.employeeDeductions))
                        }
                        if record.isSalary {
                            DisclosureGroup(L10n.text("history.deductions")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let social = record.personalSocialInsurance {
                                        LabeledContent(L10n.text("ui.employee_social_insurance.1599ba3b"), value: historyAmount(social))
                                    }
                                    if let fund = record.personalHousingFund {
                                        LabeledContent(L10n.text("ui.employee_housing_fund.a018d750"), value: historyAmount(fund))
                                    }
                                    if let employer = record.employerHousingFund {
                                        LabeledContent(L10n.text("ui.employer_housing_fund_not_deducted.02e83284"), value: historyAmount(employer))
                                    }
                                    Label(L10n.text(record.deductionsConfirmed ? "ui.verified.efbe0e16" : "ui.estimated_check_payslip.cb2a8276"), systemImage: record.deductionsConfirmed ? "checkmark.circle" : "circle.dashed")
                                        .foregroundStyle(record.deductionsConfirmed ? Color.green : .secondary)
                                }.font(.callout).padding(.top, 10)
                            }.font(.callout)
                        }
                    }.padding(.vertical, 8)
                }
            } header: {
                HStack {
                    Text(L10n.text("ui.reported_income_records.73fd79b8"))
                    Spacer()
                    Button(L10n.text("ui.add_past_income.79c5d643"), systemImage: "plus") {
                        let c = model.workCalendar.dateComponents([.year, .month], from: Date())
                        editingRecord = PayrollIncomeRecord(year: c.year!, month: c.month!, isSalary: true, income: 0, paidTax: 0, employeeDeductions: 0)
                    }.labelStyle(.iconOnly).help(L10n.text("ui.add_past_income.79c5d643"))
                }
            }
        }.formStyle(.grouped)
    }

    private func historyMetric(_ title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).font(.caption).foregroundStyle(.secondary)
            Text(model.privacy.isPrivacyModeEnabled ? "•••" : model.currency.formatAmount(amount)).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var displayPrivacySections: some View {
        Group {
        Section(L10n.text("ui.display_precision.0147b3b3")) {
                Picker(L10n.text("ui.app_amount_decimal_places.02c84c61"), selection: Binding(get: { model.currency.displayDecimalPlaces }, set: { model.currency.setDisplayPrecision($0) })) {
                    ForEach(0 ... 2, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(L10n.text("ui.menu_bar_decimal_places.ac37c0bf"), selection: Binding(get: { model.currency.menuBarDecimalPlaces }, set: { model.currency.setMenuBarPrecision($0) })) {
                    ForEach(0 ... 2, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Section(L10n.text("ui.menu_bar.a304cb9c")) {
                option(L10n.text("ui.hide_sensitive_info_immediate.db53b98c"), value: Binding(get: { model.privacy.isPrivacyModeEnabled }, set: { access.setSensitiveInformationHidden($0, privacy: model.privacy) }),
                       help: L10n.text("ui.mask_salary_rates_and_personal_cont.17c28ac3"))
                option(L10n.text("ui.hide_menu_bar_amount_when_paused.365bcaf7"), value: Binding(get: { access.hideWhenPaused }, set: { access.setHideWhenPaused($0) }),
                       help: L10n.text("ui.message.75bd0e42"))
            }
            Section(L10n.text("ui.pay_data_protection.2684cbc1")) {
                AuthorizationValidityView(access: access)
                if access.settingsUnlocked {
                Button(L10n.text("ui.revoke_all_access.47d109d6"), systemImage: "lock.fill") { access.revokeAuthorization() }
                }
                option(L10n.text("ui.require_authentication_for_income_b.6a58b99e"), value: Binding(get: { access.dashboardProtected }, set: { access.setDashboardProtected($0) }),
                       help: L10n.text("ui.protect_income_details_while_caffei.bc5ceda6"))
                    .disabled(access.isAuthenticating)
            }
        }
    }

    private var displayForm: some View {
        Form {
            Section(language.languageHeading) {
                Picker(language.languageHeading, selection: Binding(get: { language.currentLanguage }, set: { language.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { Text($0.displayName).tag($0) }
                }.labelsHidden()
            }
            Section(L10n.text("ui.theme_color.7d5ce714")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(BrewTheme.allCases) { theme in
                        Button { appearance.select(theme) } label: {
                            VStack(spacing: 7) {
                                Circle().fill(theme.color).frame(width: 24, height: 24)
                                Text(L10n.text(theme.rawValue)).font(.caption)
                            }.frame(maxWidth: .infinity).padding(10)
                                .background(appearance.theme == theme ? theme.color.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(appearance.theme == theme ? theme.color : Color.clear))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(L10n.text(theme.rawValue))
                            .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
                    }
                }
            }
            Section(L10n.text("ui.background_image.36887d9b")) {
                BackgroundImageSettingsView(appearance: appearance)
            }
            Section(L10n.text("ui.currency.6f11660c")) {
                HStack {
                    Text(L10n.text("ui.currency.745e4182"))
                    InfoHelp(text: L10n.text("ui.currency_selection_changes_display.e7033bec")).frame(width: 18, height: 18)
                    Spacer()
                    Picker(L10n.text("ui.currency.745e4182"), selection: $draft.config.currency) {
                        ForEach(SupportedCurrency.allCases) { currency in Text(currency.displayName).tag(currency) }
                    }.labelsHidden().fixedSize().id(language.effectiveLanguageCode)
                }
            }
            displayPrivacySections

        }.formStyle(.grouped)
    }

    private func input(_ title: String, key: String, unit: String, help: String? = nil) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            if let help { InfoHelp(text: help).frame(width: 18, height: 18) }
            Spacer(minLength: 12)
            Text(LocalizedStringKey(unit)).font(.caption).foregroundStyle(.secondary)
            if model.privacy.isPrivacyModeEnabled && !["days", "breakHours", "year", "month", "startYear", "startMonth", "overtime"].contains(key) {
                Text("•••").frame(width: 150, alignment: .trailing)
                    .help(L10n.text("ui.sensitive_information_is_hidden_sho.c47db71b"))
            } else {
                TextField(LocalizedStringKey(title), text: Binding(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0 }))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 150)
            }
        }
    }

    private func historyAmount(_ value: Double) -> String {
        model.privacy.isPrivacyModeEnabled ? "•••" : String(format: "%.2f", value)
    }

    private func option(_ title: String, value: Binding<Bool>, help: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            InfoHelp(text: help).frame(width: 18, height: 18)
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(BrewToggleStyle(checkbox: true, showsLabel: false))
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
    }

    private func helpRow(_ title: String, help: String) -> some View {
        HStack { Text(LocalizedStringKey(title)).foregroundStyle(.secondary); InfoHelp(text: help).frame(width: 18, height: 18); Spacer() }
    }

    private func applyChinaConfiguration(_ configuration: DayPerkConfiguration) throws {
        var config = configuration; config.currency = .cny
        try DayPerkModel.validate(config, requiresChinaPayroll: true)
        let previous = model.workCalendar
        try model.saveRegionalSettings(region: .china, input: model.regional.input, policy: .custom, timeZoneID: payTimeZone)
        config.startTime = model.workCalendar.date(bySettingHour: previous.component(.hour, from: configuration.startTime), minute: previous.component(.minute, from: configuration.startTime), second: 0, of: Date()) ?? config.startTime
        config.endTime = model.workCalendar.date(bySettingHour: previous.component(.hour, from: configuration.endTime), minute: previous.component(.minute, from: configuration.endTime), second: 0, of: Date()) ?? config.endTime
        try model.saveConfiguration(config)
    }

    private func save() {
        do {
            let configuration = try draft.validatedConfiguration()
            if page == .salary { try applyChinaConfiguration(configuration) }
            else { try model.saveConfiguration(configuration) }
            draft = ConfigurationDraft(model.configuration)
            message = L10n.text("ui.settings_saved_earnings_and_linking.0e5a739a"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
}

private func chineseWeekday(_ day: Weekday) -> String {
    switch day { case .monday: return L10n.text("ui.mon.c430f4c1"); case .tuesday: return L10n.text("ui.tue.d1378a68"); case .wednesday: return L10n.text("ui.wed.29611689"); case .thursday: return L10n.text("ui.thu.e9d3b01a"); case .friday: return L10n.text("ui.fri.572388f3"); case .saturday: return L10n.text("ui.sat.f9aa11db"); case .sunday: return L10n.text("ui.sun.ee239f39") }
}

struct PayrollRecordEditor: View {
    @ObservedObject var model: DayPerkModel
    let original: PayrollIncomeRecord
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var isSalary: Bool
    @State private var income: String
    @State private var paidTax: String
    @State private var social: String
    @State private var fund: String
    @State private var employerFund: String
    @State private var fundConfirmed: Bool
    @State private var additional: String
    @State private var basic: String
    @State private var other: String
    @State private var confirmed: Bool
    @State private var error = ""

    init(model: DayPerkModel, record: PayrollIncomeRecord) {
        self.model = model; original = record
        _date = State(initialValue: model.workCalendar.date(from: DateComponents(year: record.year, month: record.month, day: 1)) ?? Date())
        _isSalary = State(initialValue: record.isSalary)
        func value(_ x: Double) -> String {
            x.formatted(.number.locale(LocalizationManager.shared.currentLocale).grouping(.never).precision(.fractionLength(2)))
        }
        _income = State(initialValue: record.income > 0 ? value(record.income) : "")
        _paidTax = State(initialValue: record.income > 0 ? value(record.paidTax) : "")
        let guessedFund = min(record.employeeDeductions, model.breakdown.housingFund)
        _social = State(initialValue: value(record.personalSocialInsurance ?? max(0, record.employeeDeductions - guessedFund)))
        _fund = State(initialValue: value(record.personalHousingFund ?? guessedFund))
        _employerFund = State(initialValue: value(record.employerHousingFund ?? 0))
        _fundConfirmed = State(initialValue: record.housingFundConfirmed ?? false)
        _additional = State(initialValue: value(record.specialAdditionalDeduction ?? model.payroll.monthlySpecialAdditionalDeduction))
        _basic = State(initialValue: value(record.basicDeduction ?? 5000))
        _other = State(initialValue: value(record.otherDeduction ?? 0))
        _confirmed = State(initialValue: record.deductionsConfirmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(L10n.text("ui.add_edit_reported_income.4df16fd1")).font(.title2); Spacer() }.padding(22)
            Form {
                Section {
                    BrewDatePicker(title: L10n.text("ui.reporting_month_year_and_month_of_s.d93f0049"), selection: $date, calendar: model.workCalendar, monthsOnly: true)
                    Toggle(L10n.text("ui.salary_income_off_service_income.084c3404"), isOn: $isSalary)
                }
                Section(L10n.text("history.gross")) {
                    field(L10n.text("ui.actual_gross_income.94c20345"), text: $income)
                    field(L10n.text("ui.actual_tax_paid.d9ffa396"), text: $paidTax)
                }
                if isSalary {
                    Section(L10n.text("history.deductions")) {
                        field(L10n.text("ui.employee_social_insurance.1599ba3b"), text: $social)
                        field(L10n.text("ui.employee_housing_fund.a018d750"), text: $fund)
                        field(L10n.text("ui.employer_housing_fund_not_deducted.02e83284"), text: $employerFund)
                        Toggle(L10n.text("ui.housing_fund_amount_confirmed.72659dd8"), isOn: $fundConfirmed)
                    }
                    Section(L10n.text("ui.cumulative_tax_withholding.74218954")) {
                        field(L10n.text("ui.additional_deductions_this_month.45964537"), text: $additional)
                        field(L10n.text("ui.basic_deduction_this_month.921e9d15"), text: $basic)
                        field(L10n.text("ui.other_eligible_deductions.85a6b17c"), text: $other)
                    }
                    Section(L10n.text("history.verify")) {
                        Toggle(L10n.text("ui.deductions_verified_against_payslip.59e5dd38"), isOn: $confirmed)
                        Button(L10n.text("ui.estimate_contributions_from_current.56a0e651"), action: estimateContributions)
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("ui.cancel.2cd0f3be"), systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).help(L10n.text("ui.cancel.2cd0f3be")).keyboardShortcut(.cancelAction)
                Button(L10n.text("ui.save_record.93426c72"), systemImage: "checkmark", action: save)
                    .labelStyle(.iconOnly).help(L10n.text("ui.save_record.93426c72")).buttonStyle(BrewButtonStyle(prominent: true)).disabled(model.privacy.isPrivacyModeEnabled)
            }.padding(18)
        }.frame(width: 650, height: 650).preferredColorScheme(.dark)
            .tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle(checkbox: true))
            .background(model.appearance.theme.canvas)
            .actionFeedback($error, isError: true).actionToastHost()
    }

    private func estimateContributions() {
        guard let gross = LocalizedNumberInput.value(income, locale: LocalizationManager.shared.currentLocale), gross >= 0 else { error = L10n.text("ui.enter_the_income_first.efef1db2"); return }
        var config = model.payroll.configuration; config.records = []
        let estimate = PayrollCalculator.calculate(grossMonthlyIncome: gross, configuration: config)
        let format = FloatingPointFormatStyle<Double>.number.locale(LocalizationManager.shared.currentLocale).grouping(.never).precision(.fractionLength(2))
        social = estimate.employeeSocialInsurance.formatted(format); fund = estimate.housingFund.formatted(format)
        confirmed = false; fundConfirmed = false
        ActionToastCenter.shared.show(L10n.text("ui.estimated_check_payslip.cb2a8276"))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(LocalizedStringKey(title)); Spacer()
            if model.privacy.isPrivacyModeEnabled {
                Text("•••").frame(width: 160, alignment: .trailing).help(L10n.text("ui.sensitive_information_is_hidden_sho.c47db71b"))
            } else {
                TextField(L10n.text("ui.cny.7f77f23a"), text: text).multilineTextAlignment(.trailing).monospacedDigit().textFieldStyle(.roundedBorder).frame(width: 160)
            }
        }
    }

    private func save() {
        do {
            func amount(_ s: String) throws -> Double {
                guard let v = LocalizedNumberInput.value(s, locale: LocalizationManager.shared.currentLocale), v.isFinite, v >= 0 else { throw DayPerkInputError(message: L10n.text("ui.enter_valid_nonnegative_amounts_ver.b3f40d73")) }
                return v
            }
            var r = original
            let c = model.workCalendar.dateComponents([.year, .month], from: date)
            r.year = c.year!; r.month = c.month!; r.isSalary = isSalary
            r.income = try amount(income); r.paidTax = try amount(paidTax)
            if isSalary {
                r.personalSocialInsurance = try amount(social); r.personalHousingFund = try amount(fund)
                r.employerHousingFund = try amount(employerFund); r.housingFundConfirmed = fundConfirmed
                r.employeeDeductions = PayrollCalculator.money(r.personalSocialInsurance! + r.personalHousingFund!)
                r.specialAdditionalDeduction = try amount(additional); r.basicDeduction = try amount(basic)
                r.otherDeduction = try amount(other); r.deductionsConfirmed = confirmed
            } else {
                r.employeeDeductions = 0; r.personalSocialInsurance = nil; r.personalHousingFund = nil
                r.employerHousingFund = nil; r.housingFundConfirmed = nil
                r.specialAdditionalDeduction = nil; r.basicDeduction = nil; r.otherDeduction = nil
            }
            try model.upsertRecord(r); ActionToastCenter.shared.show(L10n.text("action.saved")); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// 在原生输入处理前结束框外点击的编辑，不吞掉按钮、滚动和其他输入框的事件。
private struct InputFocusDismissal: NSViewRepresentable {
    func makeNSView(context _: Context) -> FocusDismissalView {
        FocusDismissalView()
    }

    func updateNSView(_: FocusDismissalView, context _: Context) {}
}

private final class FocusDismissalView: NSView {
    private var monitor: Any?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor); self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let window = self?.window, event.window === window,
                  let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return event }
            let field = (editor.delegate as? NSView) ?? editor
            if !field.convert(field.bounds, to: nil).contains(event.locationInWindow) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
