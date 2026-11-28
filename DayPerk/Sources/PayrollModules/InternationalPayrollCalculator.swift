import Foundation

/// 海外模块以年度居民雇员估算为口径；预扣、个人申报和特殊豁免由可编辑模板明确区分。
struct InternationalPayrollCalculator: PayrollModule {
    static func tax(_ income: Double, bands: [TaxBand]) -> Double {
        bands.enumerated().reduce(0) { result, item in
            let (index, band) = item
            let upper = index + 1 < bands.count ? bands[index + 1].lower : .greatestFiniteMagnitude
            return result + max(0, min(income, upper) - band.lower) * band.rate
        }
    }

    func estimate(input: RegionalPayInput, policy: RegionalPayrollPolicy) throws -> RegionalPayEstimate {
        try policy.validate()
        guard [input.amount, input.annualBonus, input.hoursPerWeek, input.annualExtraDeduction, input.declaredMonthlySocialBase, input.previousYearGrossIncome].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1e12 }),
              input.hoursPerWeek <= 168, (0 ... 10).contains(input.childrenUnder25 ?? 0), (0 ... 120).contains(input.age), (0 ... 30).contains(input.dependants) else { throw DayPerkInputError(message: L10n.text("ui.invalid_payroll_input.99b18220")) }
        guard input.isTaxResident || policy.country == .singapore || policy.country == .custom else {
            throw DayPerkInputError(message: L10n.text("ui.this_preset_covers_resident_employe.5395a6a3"))
        }
        guard policy.effectiveEmploymentKind != .selfEmployed || input.declaredContributionsConfirmed == true else {
            throw DayPerkInputError(message: L10n.text("ui.enter_and_confirm_your_assessed_con.96b4e38d"))
        }
        var base = input.annualBase
        if policy.country == .australia, input.includesEmployerBenefit {
            let rate = policy.parameters["superRate"] ?? 0
            let cap = policy.parameters["superCap"] ?? .greatestFiniteMagnitude
            base = base / (1 + rate) <= cap ? base / (1 + rate) : max(0, base - cap * rate)
        }
        let gross = base + input.annualBonus
        if policy.country == .germany, gross > 0, base < (policy.parameters["minimumRegularAnnualPay"] ?? 24_000) {
            throw DayPerkInputError(message: L10n.text("ui.this_german_preset_covers_regular_e.10c725dd"))
        }
        var lines = policy.contributions.map { rule -> PayrollAmountLine in
            var contributionBase = max(0, min(gross, rule.ceiling ?? gross) - rule.floor)
            if policy.country == .hongKong && rule.id == "mpf" {
                // 年终奖按一次发放；逐月判断最低收入，不把门槛当成免缴税基。
                let monthly = base / 12
                let minimum = policy.parameters["mpfMonthlyMinimum"] ?? 7100
                let cap = (rule.ceiling ?? 360_000) / 12
                let covered = (18 ..< 65).contains(input.age)
                func employee(_ income: Double) -> Double { covered && income >= minimum ? min(income, cap) * rule.employeeRate : 0 }
                let own = employee(monthly) * 11 + employee(monthly + input.annualBonus)
                let employer = covered ? (min(monthly, cap) * 11 + min(monthly + input.annualBonus, cap)) * rule.employerRate : 0
                return PayrollAmountLine(id: rule.id, name: rule.name, employee: own, employer: employer,
                    deductible: min(own * rule.deductibleShare, policy.parameters["mpfDeductionCap"] ?? 18_000))
            }
            if policy.country == .macau && gross == 0 { contributionBase = 0 }
            if policy.country == .japan {
                let monthly = input.declaredMonthlySocialBase > 0 ? input.declaredMonthlySocialBase : base / 12
                if rule.id == "pension" { contributionBase = min(monthly, 650_000) * 12 + min(input.annualBonus, 1_500_000) }
                if ["health", "care", "child-support"].contains(rule.id) { contributionBase = min(monthly, 1_390_000) * 12 + min(input.annualBonus, 5_730_000) }
                if rule.id == "care" && !(40 ... 64).contains(input.age) { contributionBase = 0 }
            }
            if policy.country == .southKorea && rule.id == "pension" {
                let monthly = input.declaredMonthlySocialBase > 0 ? input.declaredMonthlySocialBase : gross / 12
                contributionBase = gross == 0 || input.age >= 60 ? 0 : min(max(monthly, policy.parameters["pensionMonthlyMinimum"] ?? 0), policy.parameters["pensionMonthlyMaximum"] ?? monthly) * 12
            }
            if policy.country == .newZealand, rule.id == "kiwisaver", input.kiwiSaverEnabled == false { contributionBase = 0 }
            if policy.country == .france {
                let ceiling = policy.parameters["socialAnnualCeiling"] ?? 48_060
                if rule.id == "cet" && gross <= ceiling { contributionBase = 0 }
                if rule.id.hasPrefix("csg-") {
                    let limited = min(gross, ceiling * 4)
                    contributionBase = limited * (policy.parameters["csgBaseRatio"] ?? 0.9825) + max(0, gross - limited)
                        + (policy.contributions.first { $0.id == "mutuelle" }?.employerMonthlyAmount ?? 0) * 12
                }
            }
            var employeeRate = rule.employeeRate
            if policy.country == .germany, rule.id == "care" {
                let hasChildren = input.hasChildren == true || (input.childrenUnder25 ?? 0) > 0
                if !hasChildren && input.age >= 23 { employeeRate += policy.parameters["childlessCareSurcharge"] ?? 0.006 }
                if hasChildren { employeeRate = max(0, employeeRate - Double(min(4, max(0, (input.childrenUnder25 ?? 0) - 1))) * (policy.parameters["careChildDiscount"] ?? 0.0025)) }
            }
            let employee = policy.country == .macau && gross == 0 ? 0 : rule.employeeMonthlyAmount.map { $0 * 12 } ?? (contributionBase * employeeRate)
            return PayrollAmountLine(id: rule.id, name: rule.name, employee: employee,
                                     employer: policy.country == .macau && gross == 0 ? 0 : rule.employerMonthlyAmount.map { $0 * 12 } ?? (contributionBase * rule.employerRate),
                                     deductible: employee * rule.deductibleShare)
        }
        if policy.country == .singapore {
            lines.removeAll { $0.id == "cpf" }
            if policy.effectiveEmploymentKind != .domesticWorker && input.cpfStatus != "foreigner" {
                guard ["citizen", "pr-third"].contains(input.cpfStatus) else { throw DayPerkInputError(message: L10n.text("ui.use_a_custom_cpf_rate_for_the_first.1e9977fd")) }
                guard base == 0 || base / 12 > 750 else { throw DayPerkInputError(message: L10n.text("ui.use_a_custom_cpf_contribution_for_m.2574ba9e")) }
                let rates: (Double, Double)
                switch input.age {
                case ...55: rates = (0.20, 0.17)
                case ...60: rates = (0.18, 0.16)
                case ...65: rates = (0.125, 0.125)
                case ...70: rates = (0.075, 0.09)
                default: rates = (0.05, 0.075)
                }
                let ordinary = min(base / 12, policy.parameters["cpfMonthlyCap"] ?? 0) * 12
                let additional = min(input.annualBonus, max(0, (policy.parameters["cpfAnnualCap"] ?? 0) - ordinary))
                let template = policy.contributions.first { $0.id == "cpf" }
                let employeeRate = rates.0 * (template?.employeeRate ?? 0.2) / 0.2
                let employerRate = rates.1 * (template?.employerRate ?? 0.17) / 0.17
                let employee = (ordinary + additional) * employeeRate
                lines.insert(PayrollAmountLine(id: "cpf", name: "CPF", employee: employee, employer: (ordinary + additional) * employerRate, deductible: employee), at: 0)
            }
        }
        let deductible = lines.reduce(0) { $0 + $1.deductible } + input.annualExtraDeduction
        let taxable = max(0, gross - deductible)
        var allowance = policy.taxAllowance
        var national = 0.0, regional = 0.0
        switch policy.country {
        case .hongKong:
            let progressive = Self.tax(max(0, taxable - allowance), bands: policy.taxBands)
            let standard = Self.tax(taxable, bands: [TaxBand(lower: 0, rate: policy.parameters["standardRate"] ?? 0.15),
                TaxBand(lower: policy.parameters["standardRateThreshold"] ?? 5_000_000, rate: policy.parameters["upperStandardRate"] ?? 0.16)])
            national = min(progressive, standard)
        case .macau:
            if input.age >= 65 { allowance = max(allowance, policy.parameters["seniorAllowance"] ?? 198_000) }
            let income = max(0, gross * (1 - (policy.parameters["standardDeductionRate"] ?? 0.25)) - deductible - allowance)
            // 职业税先扣减税款，再按法定规则将不足一元的税额进位。
            national = ceil(Self.tax(income, bands: policy.taxBands) * (1 - (policy.parameters["taxReductionRate"] ?? 0.30)) - 1e-9)
        case .unitedKingdom:
            allowance = max(0, allowance - max(0, taxable - 100_000) / 2)
            national = Self.tax(max(0, taxable - allowance), bands: policy.taxBands)
        case .australia:
            national = Self.tax(max(0, taxable - allowance), bands: policy.taxBands)
            let lito = taxable <= 37_500 ? 700 : taxable <= 45_000 ? max(0, 700 - (taxable - 37_500) * 0.05) : max(0, 325 - (taxable - 45_000) * 0.015)
            national = max(0, national - lito)
            let threshold = policy.parameters["medicareThreshold"] ?? 0
            guard taxable == 0 || threshold > 0 || taxable > 45_000 else {
                throw DayPerkInputError(message: L10n.text("ui.set_the_published_medicare_low_inco.404cc63a"))
            }
            let levy = min(taxable * 0.02, max(0, taxable - threshold) * 0.10)
            let surchargeRate = taxable > 164_000 ? 0.015 : taxable > 123_000 ? 0.0125 : taxable > 105_000 ? 0.01 : 0
            national += levy + (input.hasPrivateHospitalCover ? 0 : taxable * surchargeRate)
        case .canada:
            let personal = 16_452 - min(1, max(0, taxable - 181_440) / (258_482 - 181_440)) * (16_452 - 14_829)
            let creditContributions = lines.filter { ["cpp-base", "qpp-base", "ei", "qpip"].contains($0.id) }.reduce(0) { $0 + $1.employee }
            national = max(0, Self.tax(taxable, bands: policy.taxBands) - (personal + min(gross, 1501) + creditContributions) * 0.14)
            let rate = policy.regionalBands.first?.rate ?? 0
            if policy.subdivision == "CA-QC" {
                national *= 1 - (policy.parameters["quebecFederalAbatement"] ?? 0.165)
                let workerDeduction = min(policy.parameters["workerDeductionMaximum"] ?? 1450, gross * (policy.parameters["workerDeductionRate"] ?? 0.06))
                regional = max(0, Self.tax(max(0, taxable - workerDeduction), bands: policy.regionalBands) - policy.regionalAllowance * rate)
            } else {
                let personal = policy.subdivision == "CA-MB" ? policy.regionalAllowance * max(0, 1 - max(0, taxable - 200_000) / 200_000) : policy.regionalAllowance
                regional = max(0, Self.tax(taxable, bands: policy.regionalBands) - (personal + creditContributions) * rate)
            }
            if policy.subdivision == "CA-ON" {
                regional += max(0, regional - 5818) * 0.20 + max(0, regional - 7446) * 0.36
                regional -= min(regional, max(0, 600 - regional))
                let premium: Double
                switch taxable {
                case ...20_000: premium = 0
                case ...25_000: premium = min(300, (taxable - 20_000) * 0.06)
                case ...36_000: premium = 300 + min(150, (taxable - 25_000) * 0.06)
                case ...48_000: premium = 450 + min(150, (taxable - 36_000) * 0.25)
                case ...72_000: premium = 600 + min(150, (taxable - 48_000) * 0.25)
                default: premium = 750 + min(150, max(0, taxable - 200_600) * 0.25)
                }
                regional += premium
            } else if policy.subdivision == "CA-BC" {
                regional = max(0, regional - max(0, 690 - max(0, taxable - 25_570) * 0.0356))
            }
        case .newZealand:
            national = Self.tax(max(0, taxable - allowance), bands: policy.taxBands)
            if input.eligibleForIETC == true, gross >= 24_000, gross <= 70_000 {
                national = max(0, national - max(0, 520 - max(0, gross - 66_000) * 0.13))
            }
        case .germany:
            let income = max(0, taxable - allowance - (policy.parameters["employeeExpenseAllowance"] ?? 1230) - (policy.parameters["specialExpenseAllowance"] ?? 36))
            national = Self.germanIncomeTax(income)
            regional = min(national * 0.055, max(0, national - (policy.parameters["solidarityExemption"] ?? 20_350)) * 0.119)
            if input.paysChurchTax == true { regional += national * (policy.parameters["churchTaxRate"] ?? 0.09) }
        case .france:
            let expenses = min(taxable, min(policy.parameters["expenseDeductionMaximum"] ?? 14_555,
                max(policy.parameters["expenseDeductionMinimum"] ?? 509, taxable * (policy.parameters["expenseDeductionRate"] ?? 0.1))))
            national = Self.tax(max(0, taxable - expenses - allowance), bands: policy.taxBands)
            let reduction = max(0, (policy.parameters["decoteSingle"] ?? 897) - national * (policy.parameters["decoteRate"] ?? 0.4525))
            national = max(0, national - reduction)
        case .japan:
            let employmentDeduction = Self.japaneseSalaryDeduction(gross)
            let employmentIncome = max(0, gross - employmentDeduction)
            let basic: Double
            switch employmentIncome {
            case ...4_890_000: basic = 1_040_000
            case ...6_550_000: basic = 670_000
            case ...23_500_000: basic = 620_000
            case ...24_000_000: basic = 480_000
            case ...24_500_000: basic = 320_000
            case ...25_000_000: basic = 160_000
            default: basic = 0
            }
            let income = floor(max(0, employmentIncome - deductible - basic - Double(input.dependants) * 380_000) / 1000) * 1000
            national = floor(Self.tax(income, bands: policy.taxBands) * 1.021 / 100) * 100
            let previous = input.previousYearGrossIncome > 0 ? input.previousYearGrossIncome : gross
            let localIncome = max(0, previous - Self.japaneseSalaryDeduction(previous) - deductible - 430_000 - Double(input.dependants) * 330_000)
            regional = localIncome > 0 ? floor(localIncome * 0.1 / 100) * 100 + (policy.parameters["residentFixedLevy"] ?? 0) : 0
        case .southKorea:
            if policy.effectiveEmploymentKind == .selfEmployed {
                national = max(0, Self.tax(max(0, taxable - Double(1 + input.dependants) * 1_500_000), bands: policy.taxBands)
                    - (policy.parameters["standardBusinessTaxCredit"] ?? 0))
                regional = national * 0.1
                break
            }
            let earnedDeduction = Self.koreanSalaryDeduction(gross)
            national = Self.tax(max(0, taxable - earnedDeduction - Double(1 + input.dependants) * 1_500_000), bands: policy.taxBands)
            let credit = national <= 1_300_000 ? national * 0.55 : 715_000 + (national - 1_300_000) * 0.30
            let limit = gross <= 33_000_000 ? 740_000 : gross <= 70_000_000 ? max(660_000, 740_000 - (gross - 33_000_000) * 0.008) : gross <= 120_000_000 ? max(500_000, 660_000 - (gross - 70_000_000) * 0.5) : max(200_000, 500_000 - (gross - 120_000_000) * 0.5)
            national = max(0, national - min(credit, limit) - 130_000)
            regional = national * 0.1
        case .singapore:
            let earnedRelief = input.isTaxResident ? (input.age < 55 ? 1000.0 : input.age < 60 ? 6000 : 8000) : 0
            national = Self.tax(max(0, taxable - allowance - earnedRelief), bands: policy.taxBands)
            if !input.isTaxResident { national = max(national, gross * 0.15) }
        default:
            national = Self.tax(max(0, taxable - allowance), bands: policy.taxBands)
            regional = Self.tax(max(0, taxable - policy.regionalAllowance), bands: policy.regionalBands)
            regional = max(0, regional - (policy.parameters["regionalCredit"] ?? 0))
            if policy.country == .unitedStates && policy.subdivision == "US-CA" { regional += max(0, taxable - 1_000_000) * 0.01 }
        }
        return RegionalPayEstimate(annualGross: gross, annualIncomeTax: PayrollCalculator.money(national),
                                   annualRegionalTax: PayrollCalculator.money(regional), contributions: lines)
    }

    /// 2026 年 EStG §32a 单独评税公式，按法定顺序对税基和税额取整。
    static func germanIncomeTax(_ taxable: Double) -> Double {
        let x = floor(max(0, taxable))
        let result: Double
        switch x {
        case ...12_348: result = 0
        case ...17_799:
            let y = (x - 12_348) / 10_000
            result = (914.51 * y + 1400) * y
        case ...69_878:
            let z = (x - 17_799) / 10_000
            result = (173.1 * z + 2397) * z + 1034.87
        case ...277_825: result = 0.42 * x - 11_135.63
        default: result = 0.45 * x - 19_470.38
        }
        return floor(max(0, result))
    }

    private static func japaneseSalaryDeduction(_ gross: Double) -> Double {
        switch gross {
        case ...2_200_000: return min(gross, 740_000)
        case ...3_600_000: return gross * 0.30 + 80_000
        case ...6_600_000: return gross * 0.20 + 440_000
        case ...8_500_000: return gross * 0.10 + 1_100_000
        default: return 1_950_000
        }
    }

    private static func koreanSalaryDeduction(_ gross: Double) -> Double {
        let value: Double
        switch gross {
        case ...5_000_000: value = gross * 0.7
        case ...15_000_000: value = 3_500_000 + (gross - 5_000_000) * 0.4
        case ...45_000_000: value = 7_500_000 + (gross - 15_000_000) * 0.15
        case ...100_000_000: value = 12_000_000 + (gross - 45_000_000) * 0.05
        default: value = 14_750_000 + (gross - 100_000_000) * 0.02
        }
        return min(20_000_000, value)
    }
}
