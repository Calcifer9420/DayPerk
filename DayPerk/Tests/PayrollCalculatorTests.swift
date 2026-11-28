import Testing
@testable import DayPerk

struct PayrollCalculatorTests {
    private func withoutContributions(month: Int = 1) -> PayrollDeductionConfiguration {
        var config = PayrollDeductionConfiguration(taxMonth: month, taxYear: 2026, employmentStartMonth: 1)
        config.policy.pensionRate = 0; config.policy.medicalRate = 0; config.policy.unemploymentRate = 0
        config.policy.personalMedicalFixed = 0; config.housingFundRate = 0
        return config
    }

    @Test func housingFundOnlyDeductsTheCappedPersonalContributionFromSalary() {
        var config = withoutContributions()
        config.policy.housingBaseMinimum = 2_000; config.policy.housingBaseMaximum = 10_000
        config.housingFundRate = 0.1; config.policy.employerHousingFundRate = 0.2
        let withFund = PayrollCalculator.calculate(grossMonthlyIncome: 20_000, configuration: config)
        #expect(withFund.housingFund == 1_000 && withFund.netMonthlyIncome == 18_580)
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 40_000, configuration: config).housingFund == 1_000)
        config.housingFundBase = 500
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 40_000, configuration: config).housingFund == 200)
        config.housingFundBase = 100_000
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 40_000, configuration: config).housingFund == 1_000)
        let salaryOnly = PayrollCalculator.trackingBasis(gross: 20_000, configuration: config, includeHousingFund: false)
        #expect(salaryOnly.housingFund == 0 && salaryOnly.total == withFund.netMonthlyIncome)
    }

    @Test func cumulativeWithholdingChangesWhenTheAnnualTaxableIncomeCrossesABracket() {
        // 税务总局 2018 年第 61 号公告：累计应纳税额减去累计已预扣税额。
        let values: [(Int, Double)] = [(1, 150), (7, 150), (8, 430), (9, 500), (12, 500)]
        for (month, expected) in values {
            let result = PayrollCalculator.calculate(grossMonthlyIncome: 10_000, configuration: withoutContributions(month: month))
            #expect(result.individualIncomeTax == expected)
        }
    }

    @Test func salaryTaxIsContinuousAcrossAllAnnualBracketBoundaries() {
        let boundaries: [(Double, Double, Double)] = [
            (36_000, 1_080, 1_080.1), (144_000, 11_880, 11_880.2),
            (300_000, 43_080, 43_080.25), (420_000, 73_080, 73_080.3),
            (660_000, 145_080, 145_080.35), (960_000, 250_080, 250_080.45)
        ]
        for (taxable, atBoundary, aboveBoundary) in boundaries {
            #expect(PayrollCalculator.calculate(grossMonthlyIncome: taxable + 5_000, configuration: withoutContributions()).individualIncomeTax == atBoundary)
            #expect(PayrollCalculator.calculate(grossMonthlyIncome: taxable + 5_001, configuration: withoutContributions()).individualIncomeTax == aboveBoundary)
        }
    }

    @Test func separateBonusTaxUsesMonthlyQuickDeductionsAndRetainsBracketCliffs() {
        // 财税公告 2023 年第 30 号：奖金除以 12 选档，总额乘税率减月度速算扣除数。
        let boundaries: [(Double, Double, Double)] = [
            (36_000, 1_080, 3_390.1), (144_000, 14_190, 27_390.2),
            (300_000, 58_590, 72_340.25), (420_000, 102_340, 121_590.3),
            (660_000, 193_590, 223_840.35), (960_000, 328_840, 416_840.45)
        ]
        for (bonus, atBoundary, aboveBoundary) in boundaries {
            #expect(PayrollCalculator.annualBonusTax(for: bonus) == atBoundary)
            #expect(PayrollCalculator.annualBonusTax(for: bonus + 1) == aboveBoundary)
            #expect(bonus + 1 - aboveBoundary < bonus - atBoundary)
        }
    }

    @Test func calculatesHangzhouContributionsAndHousingFund() {
        let result = PayrollCalculator.calculate(grossMonthlyIncome: 8_000,
            configuration: PayrollDeductionConfiguration(taxMonth: 1))
        #expect(result.pensionInsurance == 640)
        #expect(result.medicalInsurance == 160)
        #expect(result.unemploymentInsurance == 40)
        #expect(result.housingFund == 960)
        #expect(result.individualIncomeTax == 36)
        #expect(result.netMonthlyIncome == 6_164)
    }

    @Test func clampsBasesAndOnlyDeductsEmployeeHousingFund() {
        let result = PayrollCalculator.calculate(grossMonthlyIncome: 100_000,
            configuration: PayrollDeductionConfiguration(taxMonth: 1))
        #expect(result.employeeSocialInsurance == 2_689.16)
        #expect(result.housingFund == 5_058)
        #expect(result.netMonthlyIncome == PayrollCalculator.money(100_000 - 2_689.16 - 5_058 - result.individualIncomeTax))
    }

    @Test func preservesActualTaxAndExcludesLaborFromSalaryWithholding() {
        let salary = PayrollIncomeRecord(year: 2026, month: 9, isSalary: true,
            income: 10_000, paidTax: 75, employeeDeductions: 2_000)
        let labor = PayrollIncomeRecord(year: 2026, month: 7, isSalary: false,
            income: 5_000, paidTax: 800, employeeDeductions: 0)
        var config = PayrollDeductionConfiguration(taxMonth: 10, taxYear: 2026,
            employmentStartMonth: 9, records: [salary])
        let result = PayrollCalculator.calculate(grossMonthlyIncome: 12_000, configuration: config)
        // 两个月累计应纳税额 219.00，减去已申报 75，不重新推算历史已缴税。
        #expect(result.individualIncomeTax == 144)
        config.records.append(labor)
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 12_000, configuration: config) == result)
        config.taxMonth = 9
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 12_000, configuration: config).individualIncomeTax == 75)
    }

    @Test func ignoresOtherYearsAndFutureRecordsAndHandlesDisabledAndInvalidInput() {
        var config = PayrollDeductionConfiguration(taxMonth: 1, taxYear: 2027)
        let baseline = PayrollCalculator.calculate(grossMonthlyIncome: 8_000, configuration: config)
        config.records = [PayrollIncomeRecord(year: 2026, month: 1, isSalary: true,
            income: 100_000, paidTax: 10_000, employeeDeductions: 0)]
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 8_000, configuration: config) == baseline)
        config.records[0].year = 2027
        config.records[0].month = 2
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 8_000, configuration: config) == baseline)
        config.isEnabled = false
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 8_000, configuration: config).netMonthlyIncome == 8_000)
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: .nan, configuration: config).netMonthlyIncome == 0)
    }
    @Test func taxesAnnualBonusBeforeAddingItToIncomeSpeed() {
        var config = PayrollDeductionConfiguration(taxMonth: 1, taxYear: 2026)
        let without = PayrollCalculator.calculate(grossMonthlyIncome: 10_000, configuration: config)
        config.includeAnnualBonus = true
        config.annualBonusBase = 10_000
        config.annualBonusMonths = 3
        let withBonus = PayrollCalculator.calculate(grossMonthlyIncome: 10_000, configuration: config)
        #expect(withBonus.annualBonusGross == 30_000)
        #expect(withBonus.annualBonusTax == 900)
        #expect(withBonus.monthlyBonusAccrual == 2_425)
        #expect(withBonus.individualIncomeTax == without.individualIncomeTax)
        #expect(withBonus.trackedMonthlyIncome == without.netMonthlyIncome + 2_425)
        #expect(PayrollCalculator.annualBonusTax(for: 36_000) == 1_080)
        #expect(PayrollCalculator.annualBonusTax(for: 36_001) == 3_390.1)
        config.taxYear = 2028
        #expect(PayrollCalculator.calculate(grossMonthlyIncome: 10_000, configuration: config).monthlyBonusAccrual == 0)
    }

}
