import Foundation
@testable import DayPerk
import Testing

struct DayPerkConfigurationTests {
    private var configuration: DayPerkConfiguration {
        DayPerkConfiguration(baseSalary: 10000, housingAllowance: 500, workdaysPerMonth: 22,
                             startTime: Date.createTime(hour: 9, minute: 0), endTime: Date.createTime(hour: 18, minute: 0),
                             weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday], overtimeMultiplier: 1,
                             dateOverrides: [:], currency: .cny, payroll: PayrollDeductionConfiguration(), followsCurrentMonth: true)
    }

    @Test func configurationRejectsInvalidAmountsTimeAndRateRanges() throws {
        try DayPerkModel.validate(configuration)
        var c = configuration; c.baseSalary = .nan
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.workdaysPerMonth = 0
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.payday.day = 32
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.endTime = c.startTime
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.payroll.policy.socialBaseMinimum = c.payroll.policy.socialBaseMaximum + 1
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.payroll.housingFundRate = 1.5
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration; c.currency = .usd
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c.payroll.isEnabled = false
        try DayPerkModel.validate(c)
        c = configuration; c.payroll.annualBonusStartDate = Date(timeIntervalSince1970: .nan)
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
    }

    @Test func customFundRateCanExceedTemplateDefaults() throws {
        var c = configuration
        c.payroll.housingFundRate = 0.3
        c.payroll.policy.employerHousingFundRate = 0.3
        c.payroll.housingFundBase = 10000
        try DayPerkModel.validate(c)
        let result = PayrollCalculator.calculate(grossMonthlyIncome: 20000, configuration: c.payroll)
        #expect(result.housingFund == 3000)
    }

    @Test func referenceBreaksReduceRateDenominatorWithoutSchedulingWork() throws {
        var c = configuration
        c.startTime = Date.createTime(hour: 9, minute: 0)
        c.endTime = Date.createTime(hour: 19, minute: 0)
        c.dailyBreakMinutes = 120
        #expect(c.workMinutesPerDay == 480)
        try DayPerkModel.validate(c)
        c.dailyBreakMinutes = 600
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
    }

    @Test func editingBackfillReplacesByIDAndDuplicateSalaryMonthsAreRejected() throws {
        let record = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true,
                                         income: 10000, paidTax: 100, employeeDeductions: 2000)
        var changed = record; changed.income = 11000
        let updated = try DayPerkModel.upserting(changed, into: [record])
        #expect(updated.count == 1 && updated[0].income == 11000)
        var duplicate = record; duplicate.id = UUID()
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.upserting(duplicate, into: [record]) }
        duplicate.isSalary = false
        #expect(try DayPerkModel.upserting(duplicate, into: [record]).count == 2)
        changed.paidTax = 12000
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.upserting(changed, into: [record]) }
    }

    @Test func legacyTaxRecordsDecodeWithoutNewOptionalBreakdownFields() throws {
        let record = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true,
                                         income: 10000, paidTax: 100, employeeDeductions: 2000)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(PayrollIncomeRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.personalHousingFund == nil && decoded.specialAdditionalDeduction == nil)
    }

    @Test func historicalDeductionsChangeFutureTaxButNeverRewriteActualPaidTax() {
        var record = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true,
                                         income: 10000, paidTax: 100, employeeDeductions: 2000)
        var c = PayrollDeductionConfiguration(taxMonth: 10, taxYear: 2026, employmentStartMonth: 9, records: [record])
        let baseline = PayrollCalculator.calculate(grossMonthlyIncome: 12000, configuration: c)
        record.specialAdditionalDeduction = 1000
        c.records = [record]
        let updated = PayrollCalculator.calculate(grossMonthlyIncome: 12000, configuration: c)
        #expect(updated.individualIncomeTax == baseline.individualIncomeTax - 30)
        c.taxMonth = 9
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 12000, configuration: c).individualIncomeTax == 100)
    }

    @Test func newYearRestartsSalaryWithholdingFromJanuary() {
        var c = PayrollDeductionConfiguration(taxMonth: 1, taxYear: 2027, employmentStartMonth: 9)
        c.employmentStartYear = 2026
        let january = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        #expect(january.individualIncomeTax > 0)
    }

    @Test func confirmedHousingFundRoundTripsAndEmployerContributionDoesNotReducePay() throws {
        var record = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true,
                                         income: 10000, paidTax: 100, employeeDeductions: 2000)
        record.personalHousingFund = 1200
        record.personalSocialInsurance = 800
        record.employerHousingFund = 1200
        record.housingFundConfirmed = true
        let decoded = try JSONDecoder().decode(PayrollIncomeRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record && decoded.housingFundConfirmed == true)
        let c = PayrollDeductionConfiguration(taxMonth: 9, taxYear: 2026, employmentStartMonth: 9, records: [decoded])
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c).netMonthlyIncome == 7900)
    }

    @Test func allBonusFundAndDeductionCombinationsUseTheSelectedBasis() {
        var c = PayrollDeductionConfiguration(contributionBase: 10000, taxMonth: 1, housingFundBase: 5000, taxYear: 2026,
                                              annualBonusBase: 10000, annualBonusMonths: 6)
        for deduct in [false, true] {
            for bonus in [false, true] {
                for fund in [false, true] {
                    c.isEnabled = deduct; c.includeAnnualBonus = bonus
                    let basis = PayrollCalculator.trackingBasis(gross: 10000, configuration: c, includeHousingFund: fund)
                    let salary = deduct ? 8249.5 : 10000
                    let monthlyBonus = bonus ? (deduct ? 4517.5 : 5000) : 0
                    #expect(abs(basis.total - (salary + monthlyBonus + (fund ? 1200 : 0))) < 0.001)
                    #expect(basis.housingFund == (fund ? 1200 : 0))
                }
            }
        }
    }

    @Test func workBreakModesAreExclusiveAndOverlappingRangesAreRejected() throws {
        var c = configuration; c.dailyBreakMinutes = 999
        c.breakMode = .timeRanges
        c.breakPeriods = [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)]
        #expect(c.workMinutesPerDay == 420)
        try DayPerkModel.validate(c)
        c.breakPeriods.append(WorkBreak(startMinute: 13 * 60, endMinute: 15 * 60))
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c.breakMode = .totalHours; c.dailyBreakMinutes = 60
        #expect(c.workMinutesPerDay == 480)
    }

    @Test func overtimeRaisesForecastTaxWithoutChangingContributionBasesOrActualTax() {
        var c = PayrollDeductionConfiguration(contributionBase: 10000, taxMonth: 1, housingFundBase: 10000, taxYear: 2026)
        let original = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        c.estimatedExtraIncomeByMonth = [1: 1000]
        let extra = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        #expect(extra.overtimeGross == 1000)
        #expect(extra.employeeSocialInsurance == original.employeeSocialInsurance && extra.housingFund == original.housingFund)
        #expect(extra.individualIncomeTax > original.individualIncomeTax)
        #expect(abs(extra.netMonthlyIncome - original.netMonthlyIncome - 970) < 0.001)
        c.records = [PayrollIncomeRecord(year: 2026, month: 1, isSalary: true, income: 10000, paidTax: 100, employeeDeductions: 2000)]
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c).individualIncomeTax == 100)
    }

    @Test func cityTemplatesPreservePersonalFactsAndUseVerifiedRules() throws {
        var c = configuration
        let record = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true, income: 10000, paidTax: 100, employeeDeductions: 2000)
        c.payroll.records = [record]
        #expect(CityPayrollTemplates.all.count == 5)
        for template in CityPayrollTemplates.all {
            let selected = template.applying(to: c)
            #expect(selected.baseSalary == c.baseSalary && selected.payroll.records == c.payroll.records)
            #expect(selected.payroll.contributionBase == c.payroll.contributionBase)
            try DayPerkModel.validate(selected)
            #expect(template.sources.allSatisfy { $0.url.hasPrefix("https://") })
            #expect(selected.payroll.policy.employerPensionRate != nil && selected.payroll.policy.employerInjuryRate != nil && selected.payroll.policy.employerUnemploymentRate != nil)
        }
        let bj = try #require(CityPayrollTemplates.all.first { $0.id == "beijing" }).applying(to: c)
        #expect(bj.payroll.policy.personalMedicalFixed == 3 && bj.payroll.policy.socialBaseMaximum == 36348)
        let sh = try #require(CityPayrollTemplates.all.first { $0.id == "shanghai" }).applying(to: c)
        #expect(sh.payroll.housingFundRate == 0.07 && sh.payroll.policy.supplementaryFundRate == 0.05)
        #expect(PayrollCalculator.housingContribution(base: 37731, basic: 0.07, supplementary: 0.05) == 4528)
        #expect(sh.payroll.policy.employerUnemploymentRate == 0.005)
        let hz = try #require(CityPayrollTemplates.all.first { $0.id == "hangzhou" }).applying(to: c)
        #expect(hz.payroll.policy.medicalIncludesMaternity == true)
        #expect(hz.payroll.policy.employerMedicalRate == 0.095 && hz.payroll.policy.employerMaternityRate == 0.006)
    }

    @Test func separateMedicalAndUnemploymentRangesAreValidated() {
        var c = configuration
        c.payroll.policy.medicalBaseMinimum = 20000; c.payroll.policy.medicalBaseMaximum = 10000
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
        c = configuration
        c.payroll.policy.unemploymentBaseMinimum = 20000; c.payroll.policy.unemploymentBaseMaximum = 10000
        #expect(throws: DayPerkInputError.self) { try DayPerkModel.validate(c) }
    }
}

@MainActor struct SalaryAccessTests {
    @Test func fullDataLockOverridesPreferencesPersistsAndRequiresFreshAuthentication() {
        let store = defaults()
        var granted = true
        var calls = 0
        let access = SalaryAccessController(defaults: store) { _, done in calls += 1; done(granted) }
        access.unlockSettings()
        access.setDashboardProtected(false)
        access.lockAllData()
        #expect(access.isDataLocked && !access.settingsUnlocked && !access.canViewIncomeDetails)
        #expect(StatusBarPresentation.amount(321, privateMode: access.isDataLocked, isWorking: true, hideWhenPaused: false).isEmpty)
        #expect(SalaryAccessController(defaults: store).isDataLocked)
        granted = false
        access.unlockAllData()
        #expect(access.isDataLocked)
        granted = true
        access.unlockAllData()
        #expect(!access.isDataLocked && access.settingsUnlocked && access.canViewIncomeDetails && calls == 4)
        #expect(!SalaryAccessController(defaults: store).isDataLocked)
    }

    @Test func nonsensitivePagesDoNotRequireWholePageUnlockAndThemesArePersistent() {
        #expect(!PreferencePage.salary.requiresWholePageUnlock)
        #expect(!PreferencePage.today.requiresWholePageUnlock)
        #expect(!PreferencePage.statistics.requiresWholePageUnlock)
        #expect(PreferencePage.history.requiresWholePageUnlock)
        let store = defaults()
        let appearance = AppearanceSettings(defaults: store)
        #expect(BrewTheme.allCases.count >= 10)
        for theme in BrewTheme.allCases {
            appearance.select(theme)
            #expect(AppearanceSettings(defaults: store).theme == theme)
        }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "salary-access-test-\(UUID().uuidString)")!
    }

    @Test func authenticationKeepsOriginalPresentationProtectedWhileFocusReturns() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let access = SalaryAccessController(defaults: defaults(), now: { clock }) { _, done in done(true) }
        var began = false
        var restored = false
        access.authenticationWillBegin = { began = access.isHandlingSystemAuthentication }
        access.authenticationDidFinish = { restored = access.isHandlingSystemAuthentication && access.settingsUnlocked }
        access.unlockSettings()
        #expect(began && restored && access.isHandlingSystemAuthentication)
        clock = clock.addingTimeInterval(1)
        #expect(!access.isHandlingSystemAuthentication && access.settingsUnlocked)
    }

    @Test func defaultsLockSensitiveViewsAndHidePausedAmount() {
        let access = SalaryAccessController(defaults: defaults())
        #expect(access.dashboardProtected && access.hideWhenPaused)
        #expect(!access.canViewIncomeDetails && !access.settingsUnlocked)
        #expect(StatusBarPresentation.amount(123, privateMode: false, isWorking: false).isEmpty)
        #expect(StatusBarPresentation.amount(123, privateMode: false, isWorking: false, hideWhenPaused: false) == "123")
        #expect(StatusBarPresentation.amount(123, privateMode: true, isWorking: true).isEmpty)
        #expect(PreferencePage.salary.containsSalaryData && PreferencePage.history.containsSalaryData && PreferencePage.today.containsSalaryData && PreferencePage.statistics.containsSalaryData)
        #expect(!PreferencePage.work.containsSalaryData && !PreferencePage.display.containsSalaryData)
    }

    @Test func failedAuthenticationNeverGrantsAccess() {
        let access = SalaryAccessController(defaults: defaults()) { _, done in done(false) }
        access.unlockSettings(); access.unlockIncomeDetails(); access.setDashboardProtected(false); access.setHideWhenPaused(false)
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails && access.dashboardProtected && access.hideWhenPaused)
    }

    @Test func revealingSensitiveInformationRequiresFreshAuthenticationButHidingDoesNot() {
        let store = defaults()
        let privacy = PrivacySettings(defaults: store)
        var granted = false
        var calls = 0
        let access = SalaryAccessController(defaults: store) { _, done in calls += 1; done(granted) }
        access.setSensitiveInformationHidden(true, privacy: privacy)
        #expect(privacy.isPrivacyModeEnabled && calls == 0)
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(privacy.isPrivacyModeEnabled && calls == 1)
        granted = true
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(!privacy.isPrivacyModeEnabled && calls == 2)
        access.setSensitiveInformationHidden(true, privacy: privacy)
        #expect(privacy.isPrivacyModeEnabled && calls == 2)
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(!privacy.isPrivacyModeEnabled && calls == 3)
    }

    @Test func hidingWhileAuthenticationIsPendingCancelsTheReveal() {
        let store = defaults()
        let privacy = PrivacySettings(defaults: store)
        var reply: ((Bool) -> Void)?
        let access = SalaryAccessController(defaults: store) { _, done in reply = done }
        access.setSensitiveInformationHidden(true, privacy: privacy)
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(access.isAuthenticating && privacy.isPrivacyModeEnabled)
        access.setSensitiveInformationHidden(true, privacy: privacy)
        reply?(true)
        #expect(privacy.isPrivacyModeEnabled && !access.isAuthenticating)
    }

    @Test func resumedTrackingRestoresMenuAmountWithoutGrantAndRespectsPrivacy() {
        let store = defaults()
        let privacy = PrivacySettings(defaults: store)
        var calls = 0
        let access = SalaryAccessController(defaults: store) { _, done in calls += 1; done(true) }
        func amount(working: Bool) -> String {
            StatusBarPresentation.amount(123, privateMode: privacy.isPrivacyModeEnabled || access.isDataLocked,
                                         isWorking: working, hideWhenPaused: access.hideWhenPaused)
        }
        #expect(amount(working: false).isEmpty)
        #expect(amount(working: true) == "123" && calls == 0)
        access.setSensitiveInformationHidden(true, privacy: privacy)
        #expect(amount(working: true).isEmpty && calls == 0)
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(amount(working: true) == "123" && calls == 1)
        access.lockAllData()
        #expect(amount(working: true).isEmpty)
    }

    @Test func tenMinuteGrantIsSharedAndDisablingAlwaysAuthenticatesAgain() {
        var calls = 0
        let store = defaults()
        let access = SalaryAccessController(defaults: store) { _, done in calls += 1; done(true) }
        access.unlockIncomeDetails()
        #expect(access.canViewIncomeDetails && access.settingsUnlocked)
        access.unlockSettings()
        #expect(access.settingsUnlocked && calls == 1)
        access.setDashboardProtected(false)
        #expect(!access.dashboardProtected && calls == 2)
        access.setDashboardProtected(true)
        #expect(access.dashboardProtected && access.canViewIncomeDetails && calls == 2)
        access.setHideWhenPaused(false)
        access.lockAll()
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
        let relaunched = SalaryAccessController(defaults: store)
        #expect(relaunched.dashboardProtected && !relaunched.hideWhenPaused && !relaunched.canViewIncomeDetails)
    }

    @Test func authenticationExpiresAfterExactlyTenMinutes() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        let access = SalaryAccessController(defaults: defaults(), now: { clock }) { _, done in calls += 1; done(true) }
        access.unlockIncomeDetails()
        clock = clock.addingTimeInterval(599)
        access.unlockSettings()
        #expect(access.settingsUnlocked && access.canViewIncomeDetails && calls == 1)
        clock = clock.addingTimeInterval(1)
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
        access.unlockSettings()
        #expect(access.settingsUnlocked && calls == 2)
    }

    @Test func cancelledRequestCannotUnlockAfterRelock() {
        var reply: ((Bool) -> Void)?
        var calls = 0
        let access = SalaryAccessController(defaults: defaults()) { _, done in calls += 1; reply = done }
        access.unlockIncomeDetails(); access.unlockSettings()
        #expect(calls == 1 && access.isAuthenticating)
        access.revokeAuthorization()
        reply?(true)
        #expect(!access.canViewIncomeDetails && !access.settingsUnlocked && !access.isAuthenticating)
    }

    @Test func manualRevokeImmediatelyInvalidatesTheSharedTenMinuteGrant() {
        var calls = 0
        let access = SalaryAccessController(defaults: defaults()) { _, done in calls += 1; done(true) }
        access.unlockSettings()
        #expect(access.settingsUnlocked && access.canViewIncomeDetails)
        access.revokeAuthorization()
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails && access.authenticatedUntil == nil)
        access.unlockIncomeDetails()
        #expect(calls == 2 && access.settingsUnlocked)
    }
}
