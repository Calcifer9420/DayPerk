import Foundation

/// 内部演示开关；公开源码始终关闭，样例文件由本机单独提供。
enum LocalPreviewMode {
    static let enabled = false
    static let bundleIdentifier = "app.dayperk.local-preview"

    static func permitsSampleData(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == Self.bundleIdentifier || bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true
    }

    static func requiresInitialSeed(defaults: any UserDataPreferences = UserDataStore.shared,
                                    bundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        // 测试版也保留用户配置；只有首次启动且存储全空时才能铺样例。
        bundleID == bundleIdentifier && defaults.dictionaryRepresentation().isEmpty
    }

    struct Seed: Decodable {
        var cityID: String
        var monthlySalary: Double
        var allowance: Double
        var annualBonusMonths: Double
        var trackedHours: Double
        var history: [SampleDay] = []
        var payrollMonths: Int = 6
        var language: String? = nil
        var policyID: String? = nil
    }

    struct SampleDay: Decodable {
        var dayOffset: Int
        var hours: Double
        var overtimeMultiplier: Double?
    }

    /// 必须先验证独立标识，再建立演示历史，禁止读写正式应用的域。
    static func prepare(_ seed: Seed, defaults: any UserDataPreferences = UserDataStore.shared,
                        bundleID: String? = Bundle.main.bundleIdentifier, now: Date = Date()) throws {
        guard permitsSampleData(bundleIdentifier: bundleID) else {
            throw DayPerkInputError(message: L10n.text("ui.sample_data_is_only_allowed_in_the.82793ddb"))
        }
        // 仅演示域重置地区，避免沿用上次体验的海外配置；正式域已在入口拒绝。
        let regional = RegionalPayrollSettings(defaults: defaults)
        if let policyID = seed.policyID {
            guard let policy = PayrollCatalog.bundled.policies.first(where: { $0.id == policyID }) else {
                throw DayPerkInputError(message: L10n.text("ui.invalid_preview_app_identifier_or_c.4e9c9dc0"))
            }
            var input = RegionalPayInput()
            input.amount = seed.monthlySalary; input.frequency = .monthly
            input.annualBonus = seed.monthlySalary * seed.annualBonusMonths
            try regional.save(region: policy.country, input: input, policy: policy, timeZoneID: policy.timeZone)
        } else {
            try regional.save(region: .china, input: RegionalPayInput(), policy: .custom, timeZoneID: "Asia/Shanghai")
        }
        if let language = seed.language, AppLanguage(rawValue: language) != nil { defaults.set(language, forKey: "appLanguage") }
        if Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true {
            defaults.removeObject(forKey: LeaveLedger.storageKey)
            defaults.removeObject(forKey: LeaveRequests.storageKey)
            defaults.removeObject(forKey: "dayperkWithdrawableBenefits")
            defaults.removeObject(forKey: "dayperkWithdrawableBenefitsV2")
        }
        defaults.set(false, forKey: "isMenuBarAmountHidden")
        defaults.set(false, forKey: "includeHousingFundInRate")
        defaults.set(false, forKey: "includeHousingFundInEstimate")
        let calendar = regional.calendar
        let today = WorkPlan().businessDayStart(for: now, calendar: calendar)
        guard seed.history.count <= 730, (0 ... 24).contains(seed.payrollMonths),
              seed.history.allSatisfy({ (-730 ... -1).contains($0.dayOffset) && $0.hours.isFinite && (0 ... 24).contains($0.hours)
                  && ($0.overtimeMultiplier.map { $0.isFinite && (0 ... 20).contains($0) } ?? true) }),
              Set(seed.history.map(\.dayOffset)).count == seed.history.count else {
            throw DayPerkInputError(message: L10n.text("ui.invalid_sample_history.f0037d6e"))
        }
        var state = WorkTrackingState()
        for row in seed.history {
            guard let date = calendar.date(byAdding: .day, value: row.dayOffset, to: today) else { continue }
            state.days.append(WorkDayTotal(id: WorkPlan.dayKey(date, calendar: calendar), seconds: row.hours * 3600,
                overtimeSeconds: row.overtimeMultiplier == nil ? 0 : row.hours * 3600, currencyCode: regional.region == .china ? "CNY" : regional.selectedPolicy.currency))
        }
        defaults.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        defaults.set(false, forKey: "allDataLocked")
        defaults.set(false, forKey: "isPrivacyModeEnabled")
    }

    static func loadSeed() throws -> Seed {
        guard permitsSampleData(bundleIdentifier: Bundle.main.bundleIdentifier),
              let resources = Bundle.main.resourceURL else {
            throw DayPerkInputError(message: L10n.text("ui.sample_data_is_only_allowed_in_the.82793ddb"))
        }
        return try JSONDecoder().decode(Seed.self, from: Data(contentsOf: resources.appendingPathComponent("LocalPreview/seed.json")))
    }

    static func apply(_ seed: Seed, to model: DayPerkModel) throws {
        guard permitsSampleData(bundleIdentifier: Bundle.main.bundleIdentifier),
              let city = CityPayrollTemplates.all.first(where: { $0.id == seed.cityID }) else {
            throw DayPerkInputError(message: L10n.text("ui.invalid_preview_app_identifier_or_c.4e9c9dc0"))
        }
        if let code = seed.language, let language = AppLanguage(rawValue: code) { LocalizationManager.shared.setLanguage(language) }
        var baseline = model.configuration
        baseline.payroll = PayrollDeductionConfiguration()
        baseline.weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        baseline.rhythm = WorkRhythm()
        baseline.dateOverrides = [:]; baseline.overtimeDates = [:]
        baseline.dayStartMinute = 240; baseline.payday = PaydayRule()
        baseline.automation = WorkAutomationRules(); baseline.linkCaffeine = false
        baseline.followsCurrentMonth = true; baseline.timeZoneID = model.regional.timeZoneID
        var config = city.applying(to: baseline)
        config.baseSalary = seed.monthlySalary
        config.housingAllowance = seed.allowance
        config.startTime = model.workCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        config.endTime = model.workCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        config.dailyBreakMinutes = 60
        config.breakMode = .totalHours
        config.payroll.annualBonusBase = seed.monthlySalary
        config.payroll.annualBonusMonths = seed.annualBonusMonths
        config.payroll.includeAnnualBonus = true
        config.payroll.contributionBase = config.payroll.policy.socialBaseMaximum
        config.payroll.housingFundBase = config.payroll.policy.housingBaseMaximum
        config.includeHousingFundInRate = false
        config.includeHousingFundInEstimate = false
        if let employment = Calendar.current.date(byAdding: .month, value: -seed.payrollMonths, to: Date()) {
            config.payroll.employmentStartYear = Calendar.current.component(.year, from: employment)
            config.payroll.employmentStartMonth = Calendar.current.component(.month, from: employment)
        }
        config.currency = .cny
        let calendar = model.workCalendar
        let today = model.tracking.plan.businessDayStart(for: Date(), calendar: calendar)
        for row in seed.history {
            if let multiplier = row.overtimeMultiplier, let date = calendar.date(byAdding: .day, value: row.dayOffset, to: today) {
                config.overtimeDates[WorkPlan.dayKey(date, calendar: calendar)] = multiplier
            }
        }
        try model.saveConfiguration(config)
        if !model.usesChinaPayroll { model.currency.setCurrency(SupportedCurrency(rawValue: model.activeCurrencyCode) ?? .usd) }
        model.payroll.records = []
        for offset in (1 ... max(1, seed.payrollMonths)).reversed() where offset <= seed.payrollMonths {
            guard let date = calendar.date(byAdding: .month, value: -offset, to: today) else { continue }
            var calculation = config.payroll
            calculation.taxYear = calendar.component(.year, from: date)
            calculation.taxMonth = calendar.component(.month, from: date)
            let result = PayrollCalculator.calculate(grossMonthlyIncome: seed.monthlySalary + seed.allowance, configuration: calculation)
            try model.upsertRecord(PayrollIncomeRecord(year: calculation.taxYear, month: calculation.taxMonth, isSalary: true,
                income: result.grossMonthlyIncome, paidTax: result.individualIncomeTax,
                employeeDeductions: result.employeeSocialInsurance + result.housingFund, deductionsConfirmed: true,
                personalSocialInsurance: result.employeeSocialInsurance, personalHousingFund: result.housingFund,
                employerHousingFund: result.housingFund, housingFundConfirmed: true))
        }
        model.refreshHistoricalData()
        if !model.usesChinaPayroll, let estimate = model.regionalEstimate {
            var records: [RegionalIncomeRecord] = []
            for offset in 1 ... max(1, seed.payrollMonths) where offset <= seed.payrollMonths {
                guard let date = calendar.date(byAdding: .month, value: -offset, to: today) else { continue }
                records.append(RegionalIncomeRecord(region: model.regional.region, currency: model.activeCurrencyCode,
                    month: String(WorkPlan.dayKey(date, calendar: calendar).prefix(7)), gross: seed.monthlySalary,
                    tax: (estimate.annualIncomeTax + estimate.annualRegionalTax) / 12,
                    employeeContributions: estimate.employeeContributions / 12))
            }
            UserDataStore.shared.set(try JSONEncoder().encode(records), forKey: "dayperkInternationalIncomeRecords")
        }
        try model.tracking.correctToday(seconds: seed.trackedHours * 3600)
        model.appearance.select(.cyan)
        var background = model.appearance.background
        background.enabled = false
        model.appearance.updateBackground(background)
    }
}
