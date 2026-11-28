import Foundation
@testable import DayPerk
import Testing

struct AnnualBonusProrationTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private var configuration: PayrollDeductionConfiguration {
        var c = PayrollDeductionConfiguration(taxMonth: 11, taxYear: 2026,
                                              includeAnnualBonus: true, annualBonusBase: 10000, annualBonusMonths: 3)
        c.annualBonusStartDate = date(2026, 8, 31)
        return c
    }

    @Test func optionalProrationIncludesTheHireDayAndRemainingFullMonths() {
        var c = configuration
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
        c.prorateAnnualBonus = true
        #expect(abs(PayrollCalculator.annualBonusProrationFactor(for: c) - (4 + 1.0 / 31) / 12) < 0.000000001)
        let result = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        #expect(result.annualBonusGross == 10080.65)
        #expect(result.annualBonusTax == 302.42)
        #expect(result.monthlyBonusAccrual == 814.85)
        c.isEnabled = false
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c).monthlyBonusAccrual == 840.05)
        c.prorateAnnualBonus = false
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
    }

    @Test func monthLengthsLeapDayAndWholeYearsUseCalendarDays() {
        var c = configuration; c.prorateAnnualBonus = true
        c.annualBonusStartDate = date(2026, 1, 1)
        #expect(PayrollCalculator.annualBonusProrationFactor(for: c) == 1)
        c.annualBonusStartDate = date(2025, 12, 31)
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
        c.annualBonusStartDate = date(2027, 1, 1)
        #expect(PayrollCalculator.annualBonusGross(for: c) == 0)
        c.taxYear = 2024; c.annualBonusStartDate = date(2024, 2, 29)
        #expect(abs(PayrollCalculator.annualBonusProrationFactor(for: c) - (10 + 1.0 / 29) / 12) < 0.000000001)
        c.taxYear = 2026; c.annualBonusStartDate = date(2026, 4, 30)
        #expect(abs(PayrollCalculator.annualBonusProrationFactor(for: c) - (8 + 1.0 / 30) / 12) < 0.000000001)
        c.annualBonusStartDate = date(2026, 12, 31)
        #expect(PayrollCalculator.annualBonusGross(for: c) == 80.65)
    }

    @Test func bonusUsesTheWholeAwardYearNotTheCurrentMonthAndRetaxesTheActualAmount() {
        var c = configuration; c.annualBonusMonths = 6
        let full = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        c.prorateAnnualBonus = true; c.annualBonusStartDate = date(2026, 7, 1)
        let partial = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        #expect(partial.annualBonusGross == 30000 && partial.annualBonusTax == 900)
        #expect(full.annualBonusTax == 5790)
        #expect(partial.individualIncomeTax == full.individualIncomeTax)
        #expect(partial.employeeSocialInsurance == full.employeeSocialInsurance && partial.housingFund == full.housingFund)
        c.taxMonth = 1
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
        c.taxMonth = 12
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
        c.includeAnnualBonus = false
        #expect(PayrollCalculator.annualBonusGross(for: c) == 30000)
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c).monthlyBonusAccrual == 0)
    }

    @Test func taxStartMonthAndHistoricalActualsRemainIndependent() {
        var c = configuration; c.employmentStartMonth = 9; c.employmentStartYear = 2026
        c.records = [PayrollIncomeRecord(year: 2026, month: 9, isSalary: true, income: 11000, paidTax: 100, employeeDeductions: 2000)]
        let baseline = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        c.prorateAnnualBonus = true
        let updated = PayrollCalculator.calculate(grossMonthlyIncome: 10000, configuration: c)
        #expect(updated.individualIncomeTax == baseline.individualIncomeTax)
        #expect(c.employmentStartMonth == 9 && c.records[0].paidTax == 100)
        let basis = PayrollCalculator.trackingBasis(gross: 10000, configuration: c, includeHousingFund: false)
        #expect(basis.bonus == updated.monthlyBonusAccrual)
    }

    @MainActor @Test func newFieldsDefaultOffAndPersistWithoutChangingTaxStart() throws {
        let suite = "DayPerk.BonusTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2026, forKey: "payrollEmploymentStartYear")
        defaults.set(9, forKey: "payrollEmploymentStartMonth")
        let settings = PayrollDeductionSettings(defaults: defaults)
        #expect(!settings.prorateAnnualBonus)
        settings.annualBonusStartDate = date(2026, 8, 31)
        settings.prorateAnnualBonus = true
        let loaded = PayrollDeductionSettings(defaults: defaults)
        #expect(loaded.configuration.prorateAnnualBonus)
        #expect(loaded.configuration.annualBonusStartDate == date(2026, 8, 31))
        #expect(loaded.employmentStartYear == 2026 && loaded.employmentStartMonth == 9)
    }

    @Test func prorationRepricesTodayWhileClosedDatesKeepTheirSettlement() {
        var c = configuration
        let now = date(2026, 11, 23)
        var plan = WorkPlan(ratePerSecond: PayrollCalculator.trackingBasis(gross: 10000, configuration: c, includeHousingFund: false).total / 10000)
        var state = WorkTrackingState()
        state.days = [WorkDayTotal(id: "2026-11-22", seconds: 100, earned: 500, ratePerSecond: 5),
                      WorkDayTotal(id: "2026-11-23", seconds: 100, earned: 0)]
        state.reprice(using: plan, at: now, calendar: Calendar(identifier: .gregorian))
        let todayBefore = state.days[1].earned
        c.prorateAnnualBonus = true
        plan.ratePerSecond = PayrollCalculator.trackingBasis(gross: 10000, configuration: c, includeHousingFund: false).total / 10000
        state.reprice(using: plan, at: now, calendar: Calendar(identifier: .gregorian))
        #expect(state.days[0].earned == 500)
        #expect(state.days[1].earned < todayBefore)
        #expect(state.days[1].seconds == 100)
    }
}
