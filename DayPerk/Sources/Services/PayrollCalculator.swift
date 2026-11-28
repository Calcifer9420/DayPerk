import Combine
import Foundation

/// 已申报收入独立保存；劳务报酬不抵扣当前单位工资的累计预扣税。
struct PayrollIncomeRecord: Codable, Identifiable, Equatable {
    var id: UUID = .init()
    var year: Int
    var month: Int
    var isSalary: Bool
    var income: Double
    var paidTax: Double
    var employeeDeductions: Double
    var deductionsConfirmed: Bool = false
    var personalSocialInsurance: Double?
    var personalHousingFund: Double?
    var employerHousingFund: Double?
    var housingFundConfirmed: Bool?
    var specialAdditionalDeduction: Double?
    var basicDeduction: Double?
    var otherDeduction: Double?
}

struct PayrollPolicy: Codable, Equatable {
    var pensionRate = 0.08
    var medicalRate = 0.02
    var unemploymentRate = 0.005
    var socialBaseMinimum = 5122.0
    var socialBaseMaximum = 25611.0
    var housingBaseMinimum = 2660.0
    var housingBaseMaximum = 42151.0
    var employerHousingFundRate = 0.12
    var medicalBaseMinimum: Double?
    var medicalBaseMaximum: Double?
    var unemploymentBaseMinimum: Double?
    var unemploymentBaseMaximum: Double?
    var personalMedicalFixed: Double?
    var supplementaryFundRate: Double?
    var employerSupplementaryFundRate: Double?
    var employerPensionRate: Double?
    var employerMedicalRate: Double?
    var employerUnemploymentRate: Double?
    var employerMaternityRate: Double?
    var medicalIncludesMaternity: Bool?
    var employerInjuryRate: Double?
    var cityTemplateID: String?
}

/// 所有个人数据仅保存在本机，不随源码分发。
final class PayrollDeductionSettings: ObservableObject {
    static let shared = PayrollDeductionSettings()
    @Published var isEnabled: Bool {
        didSet { save() }
    }

    @Published var contributionBase: Double {
        didSet { save() }
    }

    @Published var housingFundBase: Double {
        didSet { save() }
    }

    @Published var housingFundRate: Double {
        didSet { save() }
    }

    @Published var monthlySpecialAdditionalDeduction: Double {
        didSet { save() }
    }

    @Published var taxMonth: Int {
        didSet { save() }
    }

    @Published var taxYear: Int {
        didSet { save() }
    }

    @Published var employmentStartMonth: Int {
        didSet { save() }
    }

    @Published var employmentStartYear: Int {
        didSet { save() }
    }

    @Published var records: [PayrollIncomeRecord] {
        didSet { save() }
    }

    @Published var includeAnnualBonus: Bool {
        didSet { save() }
    }

    @Published var annualBonusBase: Double {
        didSet { save() }
    }

    @Published var annualBonusMonths: Double {
        didSet { save() }
    }

    @Published var prorateAnnualBonus: Bool {
        didSet { save() }
    }

    @Published var annualBonusStartDate: Date {
        didSet { save() }
    }

    @Published var policy: PayrollPolicy {
        didSet { save() }
    }

    @Published var followsCurrentMonth: Bool {
        didSet { save() }
    }

    private let defaults: any UserDataPreferences
    private var reloading = false

    init(defaults: any UserDataPreferences = UserDataStore.shared, calendar: Calendar = .current) {
        self.defaults = defaults
        followsCurrentMonth = defaults.object(forKey: "payrollFollowsCurrentMonth") as? Bool ?? true
        var loadedPolicy = defaults.data(forKey: "payrollPolicyV1").flatMap {
            try? JSONDecoder().decode(PayrollPolicy.self, from: $0)
        } ?? PayrollPolicy()
        if (loadedPolicy.cityTemplateID ?? "hangzhou") == "hangzhou", loadedPolicy.medicalIncludesMaternity == nil {
            loadedPolicy.medicalIncludesMaternity = true
            if loadedPolicy.employerMaternityRate == nil || loadedPolicy.employerMaternityRate == 0 {
                loadedPolicy.employerMaternityRate = 0.006
            }
        }
        policy = loadedPolicy
        includeAnnualBonus = defaults.bool(forKey: "payrollIncludeAnnualBonus")
        annualBonusBase = defaults.double(forKey: "payrollAnnualBonusBase")
        annualBonusMonths = defaults.object(forKey: "payrollAnnualBonusMonths") as? Double ?? 0
        isEnabled = defaults.object(forKey: "payrollDeductionEnabled") as? Bool ?? true
        contributionBase = defaults.double(forKey: "payrollContributionBase")
        housingFundBase = defaults.double(forKey: "payrollHousingFundBase")
        housingFundRate = defaults.object(forKey: "payrollHousingFundRate") as? Double ?? 0.12
        monthlySpecialAdditionalDeduction = defaults.double(forKey: "payrollMonthlySpecialAdditionalDeduction")
        let savedMonth = defaults.integer(forKey: "payrollTaxMonth")
        let savedYear = defaults.integer(forKey: "payrollTaxYear")
        let currentYear = calendar.component(.year, from: Date())
        taxYear = savedYear > 0 ? savedYear : currentYear
        taxMonth = (1 ... 12).contains(savedMonth) ? savedMonth : calendar.component(.month, from: Date())
        let start = defaults.integer(forKey: "payrollEmploymentStartMonth")
        let resolvedStartMonth = (1 ... 12).contains(start) ? start : 1
        employmentStartMonth = resolvedStartMonth
        let startYear = defaults.integer(forKey: "payrollEmploymentStartYear")
        let resolvedStartYear = startYear > 0 ? startYear : (savedYear > 0 ? savedYear : currentYear)
        employmentStartYear = resolvedStartYear
        prorateAnnualBonus = defaults.bool(forKey: "payrollProrateAnnualBonus")
        annualBonusStartDate = defaults.object(forKey: "payrollAnnualBonusStartDate") as? Date
            ?? calendar.date(from: DateComponents(year: resolvedStartYear, month: resolvedStartMonth, day: 1))
            ?? calendar.startOfDay(for: Date())
        records = defaults.data(forKey: "payrollIncomeRecords").flatMap {
            try? JSONDecoder().decode([PayrollIncomeRecord].self, from: $0)
        } ?? []
    }

    var configuration: PayrollDeductionConfiguration {
        PayrollDeductionConfiguration(
            isEnabled: isEnabled, contributionBase: contributionBase,
            monthlySpecialAdditionalDeduction: monthlySpecialAdditionalDeduction,
            taxMonth: followsCurrentMonth ? Calendar.current.component(.month, from: Date()) : taxMonth, housingFundBase: housingFundBase, housingFundRate: housingFundRate,
            taxYear: followsCurrentMonth ? Calendar.current.component(.year, from: Date()) : taxYear, employmentStartMonth: employmentStartMonth, records: records,
            includeAnnualBonus: includeAnnualBonus, annualBonusBase: annualBonusBase, annualBonusMonths: annualBonusMonths, policy: policy, employmentStartYear: employmentStartYear,
            prorateAnnualBonus: prorateAnnualBonus, annualBonusStartDate: annualBonusStartDate
        )
    }

    func reloadFromStorage() {
        let value = PayrollDeductionSettings(defaults: defaults)
        reloading = true
        followsCurrentMonth = value.followsCurrentMonth
        policy = value.policy
        includeAnnualBonus = value.includeAnnualBonus
        annualBonusBase = value.annualBonusBase
        annualBonusMonths = value.annualBonusMonths
        isEnabled = value.isEnabled
        contributionBase = value.contributionBase
        housingFundBase = value.housingFundBase
        housingFundRate = value.housingFundRate
        monthlySpecialAdditionalDeduction = value.monthlySpecialAdditionalDeduction
        taxMonth = value.taxMonth
        taxYear = value.taxYear
        employmentStartMonth = value.employmentStartMonth
        employmentStartYear = value.employmentStartYear
        prorateAnnualBonus = value.prorateAnnualBonus
        annualBonusStartDate = value.annualBonusStartDate
        records = value.records
        reloading = false
    }

    private func save() {
        guard !reloading else { return }
        defaults.set(followsCurrentMonth, forKey: "payrollFollowsCurrentMonth")
        if let data = try? JSONEncoder().encode(policy) {
            defaults.set(data, forKey: "payrollPolicyV1")
        }
        defaults.set(includeAnnualBonus, forKey: "payrollIncludeAnnualBonus")
        defaults.set(annualBonusBase, forKey: "payrollAnnualBonusBase")
        defaults.set(annualBonusMonths, forKey: "payrollAnnualBonusMonths")
        defaults.set(prorateAnnualBonus, forKey: "payrollProrateAnnualBonus")
        defaults.set(annualBonusStartDate, forKey: "payrollAnnualBonusStartDate")
        defaults.set(isEnabled, forKey: "payrollDeductionEnabled")
        defaults.set(contributionBase, forKey: "payrollContributionBase")
        defaults.set(housingFundBase, forKey: "payrollHousingFundBase")
        defaults.set(housingFundRate, forKey: "payrollHousingFundRate")
        defaults.set(monthlySpecialAdditionalDeduction, forKey: "payrollMonthlySpecialAdditionalDeduction")
        defaults.set(taxMonth, forKey: "payrollTaxMonth")
        defaults.set(taxYear, forKey: "payrollTaxYear")
        defaults.set(employmentStartMonth, forKey: "payrollEmploymentStartMonth")
        defaults.set(employmentStartYear, forKey: "payrollEmploymentStartYear")
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: "payrollIncomeRecords")
        }
    }
}

struct PayrollDeductionConfiguration: Equatable {
    var isEnabled: Bool = true
    var contributionBase: Double = 0
    var monthlySpecialAdditionalDeduction: Double = 0
    var taxMonth: Int = Calendar.current.component(.month, from: Date())
    var housingFundBase: Double = 0
    var housingFundRate: Double = 0.12
    var taxYear: Int = Calendar.current.component(.year, from: Date())
    var employmentStartMonth: Int = 1
    var records: [PayrollIncomeRecord] = []
    var includeAnnualBonus: Bool = false
    var annualBonusBase: Double = 0
    var annualBonusMonths: Double = 0
    var policy = PayrollPolicy()
    var employmentStartYear: Int? = nil
    var estimatedExtraIncomeByMonth: [Int: Double] = [:]
    var estimatedUnpaidLeaveByMonth: [Int: Double] = [:]
    var prorateAnnualBonus = false
    var annualBonusStartDate = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1))!
}

struct PayrollBreakdown: Equatable {
    let grossMonthlyIncome: Double
    let pensionInsurance: Double
    let medicalInsurance: Double
    let unemploymentInsurance: Double
    let employeeSocialInsurance: Double
    let individualIncomeTax: Double
    let netMonthlyIncome: Double
    let housingFund: Double
    var overtimeGross: Double = 0
    var annualBonusGross: Double = 0
    var annualBonusTax: Double = 0
    var monthlyBonusAccrual: Double = 0
    var trackedMonthlyIncome: Double {
        netMonthlyIncome + monthlyBonusAccrual
    }

    static let zero = PayrollBreakdown(grossMonthlyIncome: 0, pensionInsurance: 0, medicalInsurance: 0,
                                       unemploymentInsurance: 0, employeeSocialInsurance: 0,
                                       individualIncomeTax: 0, netMonthlyIncome: 0, housingFund: 0)
}

struct CompensationBasis: Equatable {
    var salary: Double
    var housingFund: Double
    var bonus: Double
    var total: Double {
        salary + housingFund + bonus
    }
}

enum PayrollCalculator {
    // 杭州企业职工个人缴费参考参数；2026 政策原文部分受访问限制，需按工资条复核。
    static let socialBaseRange = 5122.0 ... 25611.0
    static let housingBaseRange = 2660.0 ... 42151.0

    static func calculate(grossMonthlyIncome: Double, configuration: PayrollDeductionConfiguration) -> PayrollBreakdown {
        let baseGross = nonnegative(grossMonthlyIncome)
        let extra = nonnegative(configuration.estimatedExtraIncomeByMonth[configuration.taxMonth] ?? 0)
        let gross = max(0, baseGross - nonnegative(configuration.estimatedUnpaidLeaveByMonth[configuration.taxMonth] ?? 0)) + extra
        let bonus = configuration.includeAnnualBonus ? annualBonusGross(for: configuration) : 0
        // 单独计税政策有效至 2027 年底，后续年份未经更新不计入预测。
        let supportedBonus = configuration.taxYear <= 2027 ? bonus : 0
        let bonusTax = configuration.isEnabled ? annualBonusTax(for: supportedBonus) : 0
        let bonusAccrual = money(max(0, supportedBonus - bonusTax) / 12)
        guard configuration.isEnabled, gross > 0 else {
            return PayrollBreakdown(grossMonthlyIncome: gross, pensionInsurance: 0, medicalInsurance: 0,
                                    unemploymentInsurance: 0, employeeSocialInsurance: 0,
                                    individualIncomeTax: 0, netMonthlyIncome: gross, housingFund: 0, overtimeGross: extra,
                                    annualBonusGross: supportedBonus, annualBonusTax: bonusTax, monthlyBonusAccrual: bonusAccrual)
        }
        let socialLow = nonnegative(configuration.policy.socialBaseMinimum)
        let socialHigh = max(socialLow, nonnegative(configuration.policy.socialBaseMaximum))
        let housingLow = nonnegative(configuration.policy.housingBaseMinimum)
        let housingHigh = max(housingLow, nonnegative(configuration.policy.housingBaseMaximum))
        let base = clamp(configuration.contributionBase > 0 ? configuration.contributionBase : baseGross, to: socialLow ... socialHigh)
        let pension = money(base * configuration.policy.pensionRate)
        let medicalLow = nonnegative(configuration.policy.medicalBaseMinimum ?? socialLow)
        let medicalHigh = max(medicalLow, nonnegative(configuration.policy.medicalBaseMaximum ?? socialHigh))
        let medicalBase = clamp(configuration.contributionBase > 0 ? configuration.contributionBase : baseGross, to: medicalLow ... medicalHigh)
        let unemploymentLow = nonnegative(configuration.policy.unemploymentBaseMinimum ?? socialLow)
        let unemploymentHigh = max(unemploymentLow, nonnegative(configuration.policy.unemploymentBaseMaximum ?? socialHigh))
        let unemploymentBase = clamp(configuration.contributionBase > 0 ? configuration.contributionBase : baseGross, to: unemploymentLow ... unemploymentHigh)
        let medical = money(medicalBase * configuration.policy.medicalRate + nonnegative(configuration.policy.personalMedicalFixed ?? 0))
        let unemployment = money(unemploymentBase * configuration.policy.unemploymentRate)
        let social = money(pension + medical + unemployment)
        let fundBase = clamp(configuration.housingFundBase > 0 ? configuration.housingFundBase : baseGross, to: housingLow ... housingHigh)
        let rate = min(1, nonnegative(configuration.housingFundRate))
        // 杭州公积金个人月缴存额按元四舍五入；只减个人部分，不重复减单位部分。
        let fund = housingContribution(base: fundBase, basic: rate, supplementary: configuration.policy.supplementaryFundRate ?? 0)
        let currentDeduction = money(social + fund)
        let additional = nonnegative(configuration.monthlySpecialAdditionalDeduction)
        let month = min(12, max(1, configuration.taxMonth))
        let start = configuration.taxYear > (configuration.employmentStartYear ?? configuration.taxYear)
            ? 1 : min(12, max(1, configuration.employmentStartMonth))
        let wageRecords = configuration.records.filter {
            $0.isSalary && $0.year == configuration.taxYear && (start ... 12).contains($0.month)
        }
        var cumulativeIncome = 0.0
        var cumulativeDeductions = 0.0
        var cumulativePaidTax = 0.0
        var cumulativeAllowances = 0.0
        var currentTax = 0.0
        if start <= month {
            for m in start ... month {
                let actual = wageRecords.filter { $0.month == m }
                cumulativeIncome += actual.isEmpty ? max(0, baseGross - nonnegative(configuration.estimatedUnpaidLeaveByMonth[m] ?? 0)) + nonnegative(configuration.estimatedExtraIncomeByMonth[m] ?? 0) : actual.reduce(0) { $0 + nonnegative($1.income) }
                cumulativeDeductions += actual.isEmpty ? currentDeduction : actual.reduce(0) {
                    $0 + nonnegative($1.employeeDeductions) + nonnegative($1.otherDeduction ?? 0)
                }
                cumulativeAllowances += nonnegative(actual.first?.basicDeduction ?? 5000)
                    + nonnegative(actual.first?.specialAdditionalDeduction ?? additional)
                let taxable = max(0, cumulativeIncome - cumulativeDeductions - cumulativeAllowances)
                // 已申报税额是事实；缺失月份才预测，不能把历史工资全部替换为当前月薪。
                let due = actual.isEmpty ? max(0, money(tax(for: taxable)) - cumulativePaidTax)
                    : actual.reduce(0) { $0 + nonnegative($1.paidTax) }
                cumulativePaidTax = money(cumulativePaidTax + due)
                if m == month {
                    currentTax = money(due)
                }
            }
        }
        let actualCurrent = wageRecords.filter { $0.month == month }
        let currentGross = actualCurrent.isEmpty ? gross : actualCurrent.reduce(0) { $0 + nonnegative($1.income) }
        let deduction = actualCurrent.isEmpty ? currentDeduction : actualCurrent.reduce(0) { $0 + nonnegative($1.employeeDeductions) }
        return PayrollBreakdown(grossMonthlyIncome: money(currentGross), pensionInsurance: pension,
                                medicalInsurance: medical, unemploymentInsurance: unemployment,
                                employeeSocialInsurance: social, individualIncomeTax: currentTax,
                                netMonthlyIncome: money(max(0, currentGross - deduction - currentTax)), housingFund: fund, overtimeGross: actualCurrent.isEmpty ? extra : 0,
                                annualBonusGross: supportedBonus, annualBonusTax: bonusTax, monthlyBonusAccrual: bonusAccrual)
    }

    /// 计费口径与实际申报分离；公积金是税外展示项，不再次参与个税。
    static func trackingBasis(gross: Double, configuration: PayrollDeductionConfiguration, includeHousingFund: Bool) -> CompensationBasis {
        let actual = configuration.records.filter { $0.isSalary && $0.year == configuration.taxYear && $0.month == configuration.taxMonth }
        let income = actual.isEmpty ? gross : actual.reduce(0) { $0 + $1.income }
        let selected = calculate(grossMonthlyIncome: income, configuration: configuration)
        var referenceConfig = configuration
        referenceConfig.isEnabled = true
        let reference = calculate(grossMonthlyIncome: income, configuration: referenceConfig)
        let low = nonnegative(configuration.policy.housingBaseMinimum)
        let high = max(low, nonnegative(configuration.policy.housingBaseMaximum))
        let base = clamp(configuration.housingFundBase > 0 ? configuration.housingFundBase : income, to: low ... high)
        let personal = actual.first?.personalHousingFund ?? reference.housingFund
        let employer = actual.first?.employerHousingFund ?? housingContribution(base: base, basic: configuration.policy.employerHousingFundRate, supplementary: configuration.policy.employerSupplementaryFundRate ?? 0)
        return CompensationBasis(salary: selected.netMonthlyIncome,
                                 housingFund: includeHousingFund ? money(personal + employer) : 0,
                                 bonus: selected.monthlyBonusAccrual)
    }

    static func housingContribution(base: Double, basic: Double, supplementary: Double) -> Double {
        let first = min(1, nonnegative(basic))
        let second = min(max(0, 1 - first), nonnegative(supplementary))
        return (base * first).rounded(.toNearestOrAwayFromZero) + (base * second).rounded(.toNearestOrAwayFromZero)
    }

    /// 入职当月包含入职当天，按自然日折算；之后完整月份按月计至该年年底。
    static func annualBonusProrationFactor(for configuration: PayrollDeductionConfiguration,
                                          calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        guard configuration.prorateAnnualBonus else { return 1 }
        let date = configuration.annualBonusStartDate
        guard date.timeIntervalSince1970.isFinite else { return 0 }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let days = calendar.range(of: .day, in: .month, for: date)?.count else { return 0 }
        if year < configuration.taxYear { return 1 }
        if year > configuration.taxYear { return 0 }
        return (Double(12 - month) + Double(days - day + 1) / Double(days)) / 12
    }

    /// 预计奖金独立于是否摊入计费，供设置预览及计费共用。
    static func annualBonusGross(for configuration: PayrollDeductionConfiguration) -> Double {
        money(nonnegative(configuration.annualBonusBase) * nonnegative(configuration.annualBonusMonths)
            * annualBonusProrationFactor(for: configuration))
    }

    /// 奖金除以 12 只用于选税率；税额按奖金总额计算，速算扣除数使用月度值。
    static func annualBonusTax(for amount: Double) -> Double {
        let value = nonnegative(amount)
        let result: Double
        switch value {
        case ...36000: result = value * 0.03
        case ...144_000: result = value * 0.10 - 210
        case ...300_000: result = value * 0.20 - 1410
        case ...420_000: result = value * 0.25 - 2660
        case ...660_000: result = value * 0.30 - 4410
        case ...960_000: result = value * 0.35 - 7160
        default: result = value * 0.45 - 15160
        }
        return money(result)
    }

    static func money(_ value: Double) -> Double {
        var input = Decimal(nonnegative(value))
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return Double(NSDecimalNumber(decimal: result).stringValue) ?? 0
    }

    private static func nonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(nonnegative(value), range.lowerBound), range.upperBound)
    }

    private static func tax(for income: Double) -> Double {
        switch income {
        case ...36000: return income * 0.03
        case ...144_000: return income * 0.10 - 2520
        case ...300_000: return income * 0.20 - 16920
        case ...420_000: return income * 0.25 - 31920
        case ...660_000: return income * 0.30 - 52920
        case ...960_000: return income * 0.35 - 85920
        default: return income * 0.45 - 181_920
        }
    }
}
