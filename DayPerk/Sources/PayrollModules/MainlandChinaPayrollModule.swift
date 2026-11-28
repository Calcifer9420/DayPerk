import Foundation

/// 中国大陆保留累计预扣、申报历史和单独计税年终奖，公共接口只转换结果格式。
struct MainlandChinaPayrollModule: PayrollModule {
    var configuration: PayrollDeductionConfiguration
    func monthly(gross: Double) -> PayrollBreakdown {
        PayrollCalculator.calculate(grossMonthlyIncome: gross, configuration: configuration)
    }
    func estimate(input: RegionalPayInput, policy: RegionalPayrollPolicy) throws -> RegionalPayEstimate {
        guard policy.country == .china else { throw DayPerkInputError(message: L10n.text("ui.invalid_mainland_china_policy.162210f2")) }
        let monthly = monthly(gross: input.annualBase / 12)
        return RegionalPayEstimate(annualGross: monthly.grossMonthlyIncome * 12,
            annualIncomeTax: monthly.individualIncomeTax * 12, annualRegionalTax: 0,
            contributions: [PayrollAmountLine(id: "social", name: L10n.text("ui.employee_social_insurance.1599ba3b"), employee: monthly.employeeSocialInsurance * 12, employer: 0),
                PayrollAmountLine(id: "housing", name: L10n.text("ui.housing_fund.397c8572"), employee: monthly.housingFund * 12,
                    employer: min(max(configuration.housingFundBase, configuration.policy.housingBaseMinimum), configuration.policy.housingBaseMaximum) * configuration.policy.employerHousingFundRate * 12)])
    }
}
