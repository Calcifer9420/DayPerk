import Combine
import Foundation

enum PayrollRegion: String, CaseIterable, Codable, Identifiable {
    case china = "CN", hongKong = "HK", macau = "MO", singapore = "SG", australia = "AU", unitedStates = "US", canada = "CA", unitedKingdom = "GB", japan = "JP", southKorea = "KR", newZealand = "NZ", germany = "DE", france = "FR", custom = "CUSTOM"
    var id: String { rawValue }
    var name: String { L10n.text("payroll.region." + rawValue) }
    var currencyCode: String {
        [Self.china: "CNY", .hongKong: "HKD", .macau: "MOP", .singapore: "SGD", .australia: "AUD", .unitedStates: "USD", .canada: "CAD", .unitedKingdom: "GBP", .japan: "JPY", .southKorea: "KRW", .newZealand: "NZD", .germany: "EUR", .france: "EUR", .custom: "EUR"][self]!
    }
}

enum PayFrequency: String, Codable, CaseIterable, Identifiable {
    case hourly = "Hourly", weekly = "Weekly", fortnightly = "Every two weeks", semimonthly = "Twice a month", monthly = "Monthly", annual = "Annual"
    var id: String { rawValue }
    func periods(hoursPerWeek: Double) -> Double {
        switch self {
        case .hourly: return 52 * hoursPerWeek
        case .weekly: return 52
        case .fortnightly: return 26
        case .semimonthly: return 24
        case .monthly: return 12
        case .annual: return 1
        }
    }
}

struct TaxBand: Codable, Equatable, Identifiable {
    var lower: Double
    var rate: Double
    var id: Double { lower }
}

struct ContributionRule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var employeeRate: Double
    var employerRate: Double
    var floor: Double = 0
    var ceiling: Double?
    var deductibleShare: Double = 0
    var employeeMonthlyAmount: Double?
    var employerMonthlyAmount: Double?
}

enum PayrollEmploymentKind: String, Codable, CaseIterable, Identifiable {
    case employee = "Employee", domesticWorker = "Migrant domestic worker", selfEmployed = "Self-employed"
    var id: String { rawValue }
}

struct PolicySource: Codable, Equatable, Identifiable {
    var title: String
    var url: String
    var id: String { url }
}

struct RegionalPayrollPolicy: Codable, Equatable, Identifiable {
    var id: String
    var country: PayrollRegion
    var city: String
    var subdivision: String
    var currency: String
    var timeZone: String
    var taxYear: Int
    var taxYearStartMonth: Int = 1
    var taxYearStartDay: Int = 1
    var validFrom: String
    var validThrough: String
    var sources: [PolicySource]
    var assumptions: [String]
    var taxBands: [TaxBand]
    var taxAllowance: Double
    var regionalBands: [TaxBand] = []
    var regionalAllowance: Double = 0
    var contributions: [ContributionRule] = []
    var parameters: [String: Double] = [:]
    var employmentKind: PayrollEmploymentKind?
    var effectiveEmploymentKind: PayrollEmploymentKind { employmentKind ?? .employee }

    static var custom: Self {
        Self(id: "custom", country: .custom, city: "Custom", subdivision: "", currency: "EUR", timeZone: TimeZone.current.identifier,
             taxYear: Calendar.current.component(.year, from: Date()), validFrom: "", validThrough: "", sources: [], assumptions: [],
             taxBands: [TaxBand(lower: 0, rate: 0)], taxAllowance: 0)
    }

    func validate() throws {
        var numbers = [taxAllowance, regionalAllowance] + Array(parameters.values)
        numbers += taxBands.flatMap { [$0.lower, $0.rate] }
        numbers += regionalBands.flatMap { [$0.lower, $0.rate] }
        for rule in contributions {
            numbers += [rule.employeeRate, rule.employerRate, rule.floor, rule.ceiling ?? 0,
                        rule.deductibleShare, rule.employeeMonthlyAmount ?? 0, rule.employerMonthlyAmount ?? 0]
        }
        guard numbers.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1e15 }), TimeZone(identifier: timeZone) != nil,
              currency.count == 3, SupportedCurrency(rawValue: currency) != nil,
              sources.allSatisfy({ URL(string: $0.url)?.scheme == "https" }),
              !id.isEmpty, taxBands.count <= 30, regionalBands.count <= 30, contributions.count <= 40,
              (2020 ... 2100).contains(taxYear), (1 ... 12).contains(taxYearStartMonth), (1 ... 31).contains(taxYearStartDay),
              Set(contributions.map(\.id)).count == contributions.count else { throw DayPerkInputError(message: L10n.text("ui.invalid_payroll_configuration.5fb47440")) }
        for bands in [taxBands, regionalBands] {
            guard bands.allSatisfy({ $0.rate <= 1 }), bands.map(\.lower) == bands.map(\.lower).sorted(),
                  Set(bands.map(\.lower)).count == bands.count else { throw DayPerkInputError(message: L10n.text("ui.tax_bands_must_be_ordered_and_rates.c1de98c3")) }
        }
        guard contributions.allSatisfy({ $0.employeeRate <= 1 && $0.employerRate <= 1 && $0.deductibleShare <= 1 && ($0.ceiling ?? .greatestFiniteMagnitude) >= $0.floor }) else {
            throw DayPerkInputError(message: L10n.text("ui.contribution_rates_or_limits_are_in.90d75771"))
        }
    }
}

struct RegionalPayInput: Codable, Equatable {
    var amount: Double = 0
    var frequency: PayFrequency = .monthly
    var hoursPerWeek: Double = 40
    var annualBonus: Double = 0
    var age: Int = 35
    var dependants: Int = 0
    var isTaxResident = true
    var annualExtraDeduction: Double = 0
    var declaredMonthlySocialBase: Double = 0
    var previousYearGrossIncome: Double = 0
    var includesEmployerBenefit = false
    var hasPrivateHospitalCover = true
    var cpfStatus = "citizen"
    var kiwiSaverEnabled: Bool?
    var eligibleForIETC: Bool?
    var hasChildren: Bool?
    var paysChurchTax: Bool?
    var childrenUnder25: Int?
    var declaredContributionsConfirmed: Bool?
    var annualBase: Double { amount * frequency.periods(hoursPerWeek: hoursPerWeek) }
}

struct PayrollAmountLine: Identifiable {
    var id: String
    var name: String
    var employee: Double
    var employer: Double
    var deductible: Double = 0
}

struct RegionalPayEstimate {
    var annualGross: Double
    var annualIncomeTax: Double
    var annualRegionalTax: Double
    var contributions: [PayrollAmountLine]
    var cashNet: Double { max(0, annualGross - annualIncomeTax - annualRegionalTax - contributions.reduce(0) { $0 + $1.employee }) }
    var employeeContributions: Double { contributions.reduce(0) { $0 + $1.employee } }
    var employerContributions: Double { contributions.reduce(0) { $0 + $1.employer } }
}

protocol PayrollModule {
    func estimate(input: RegionalPayInput, policy: RegionalPayrollPolicy) throws -> RegionalPayEstimate
}

final class RegionalPayrollSettings: ObservableObject {
    @Published private(set) var region: PayrollRegion
    @Published private(set) var input: RegionalPayInput
    @Published private(set) var selectedPolicy: RegionalPayrollPolicy
    @Published private(set) var benefits: [String: WithdrawableBenefit]
    @Published private(set) var benefitLists: [String: [WithdrawableBenefit]]
    private(set) var benefitStorageError: Error?
    @Published private(set) var timeZoneID: String
    @Published private(set) var manualCalendars: [String: [String: Bool]]
    private let defaults: any UserDataPreferences

    init(defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        region = PayrollRegion(rawValue: defaults.string(forKey: "dayperkPayrollRegion") ?? "CN") ?? .china
        input = defaults.data(forKey: "dayperkRegionalPayInput").flatMap { try? JSONDecoder().decode(RegionalPayInput.self, from: $0) } ?? RegionalPayInput()
        selectedPolicy = defaults.data(forKey: "dayperkRegionalPolicy").flatMap { try? JSONDecoder().decode(RegionalPayrollPolicy.self, from: $0) } ?? .custom
        manualCalendars = defaults.data(forKey: "dayperkRegionalDateOverrides").flatMap { try? JSONDecoder().decode([String: [String: Bool]].self, from: $0) } ?? [:]
        benefits = defaults.data(forKey: "dayperkWithdrawableBenefits").flatMap { try? JSONDecoder().decode([String: WithdrawableBenefit].self, from: $0) } ?? [:]
        benefitLists = [:]
        if let data = defaults.data(forKey: "dayperkWithdrawableBenefitsV2") {
            do {
                let values = try JSONDecoder().decode([String: [WithdrawableBenefit]].self, from: data)
                for (key, list) in values {
                    guard let raw = key.split(separator: ":").first, let country = PayrollRegion(rawValue: String(raw)) else {
                        throw CocoaError(.propertyListReadCorrupt)
                    }
                    try WithdrawableBenefit.validate(list, region: country)
                }
                benefitLists = values
            } catch { benefitStorageError = error }
        }
        timeZoneID = defaults.string(forKey: "dayperkWorkTimeZone") ?? TimeZone.current.identifier
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        c.firstWeekday = 2
        return c
    }

    static func benefitKey(region: PayrollRegion, currency: String) -> String { region.rawValue + ":" + currency }
    func benefit(region: PayrollRegion, currency: String) -> WithdrawableBenefit {
        let value = benefits[Self.benefitKey(region: region, currency: currency)] ?? WithdrawableBenefit()
        return (try? value.validate()) != nil ? value : WithdrawableBenefit()
    }
    var benefit: WithdrawableBenefit { benefit(region: region, currency: selectedPolicy.currency) }
    func saveBenefit(_ value: WithdrawableBenefit) throws {
        try value.validate()
        let currency = selectedPolicy.currency
        var list = withdrawableBenefits(region: region, currency: currency)
        if let i = list.firstIndex(where: { !$0.usesHousingFundAmount }) { list[i] = value }
        else { list.append(value) }
        try saveBenefits(list, region: region, currency: currency)
    }
    func withdrawableBenefits(region: PayrollRegion, currency: String) -> [WithdrawableBenefit] {
        let key = Self.benefitKey(region: region, currency: currency)
        if let saved = benefitLists[key] { return saved }
        var values: [WithdrawableBenefit] = []
        if let legacy = benefits[key], legacy.isConfigured, (try? legacy.validate()) != nil { values.append(legacy) }
        return values
    }

    /// 只把旧版已选择的公积金提取额转为固定手填收入，之后不再随缴费联动。
    func migrateHousingFundIncome(monthlyAmount: Double, currency: String) throws {
        let key = Self.benefitKey(region: .china, currency: currency)
        var values = withdrawableBenefits(region: .china, currency: currency)
        if benefitLists[key] == nil,
           defaults.bool(forKey: "includeHousingFundInRate") || defaults.bool(forKey: "includeHousingFundInEstimate") {
            values.insert(WithdrawableBenefit(id: "housing-fund",
                includeInRate: defaults.bool(forKey: "includeHousingFundInRate"),
                showInEstimate: defaults.bool(forKey: "includeHousingFundInEstimate"), usesHousingFundAmount: true), at: 0)
        }
        guard values.contains(where: \.usesHousingFundAmount) else { return }
        values = values.map { item in
            guard item.usesHousingFundAmount else { return item }
            var fixed = item
            fixed.monthlyAmount = monthlyAmount
            if fixed.name.isEmpty { fixed.name = L10n.text("ui.housing_fund_employee_employer.d802d0be") }
            fixed.usesHousingFundAmount = false
            return fixed
        }
        try saveBenefits(values, region: .china, currency: currency)
    }
    func saveBenefits(_ values: [WithdrawableBenefit], region: PayrollRegion, currency: String) throws {
        if let benefitStorageError { throw benefitStorageError }
        guard currency.count == 3, currency.allSatisfy(\.isUppercase) else { throw CocoaError(.validationMissingMandatoryProperty) }
        try WithdrawableBenefit.validate(values, region: region)
        let key = Self.benefitKey(region: region, currency: currency)
        var next = benefitLists, legacy = benefits
        next[key] = values
        legacy[key] = values.first { !$0.usesHousingFundAmount } ?? WithdrawableBenefit(id: "legacy")
        let changes: [String: Any] = ["dayperkWithdrawableBenefitsV2": try JSONEncoder().encode(next),
            "dayperkWithdrawableBenefits": try JSONEncoder().encode(legacy)]
        try defaults.persist(changes)
        benefitLists = next; benefits = legacy
    }

    var calendarKey: String { region.rawValue + ":" + selectedPolicy.subdivision }
    var manualOverrides: [String: Bool] { manualCalendars[calendarKey] ?? [:] }
    func updateOverrides(_ value: [String: Bool], persist: Bool = true) {
        manualCalendars[calendarKey] = value
        if persist { defaults.set(try? JSONEncoder().encode(manualCalendars), forKey: "dayperkRegionalDateOverrides") }
    }

    func save(region: PayrollRegion, input: RegionalPayInput, policy: RegionalPayrollPolicy, timeZoneID: String) throws {
        try policy.validate()
        guard [input.amount, input.hoursPerWeek, input.annualBonus, input.annualExtraDeduction, input.declaredMonthlySocialBase, input.previousYearGrossIncome].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1e12 }),
              input.hoursPerWeek <= 168, (0 ... 10).contains(input.childrenUnder25 ?? 0), (0 ... 120).contains(input.age), (0 ... 30).contains(input.dependants),
              TimeZone(identifier: timeZoneID) != nil, region == .china || policy.country == region else { throw DayPerkInputError(message: L10n.text("ui.invalid_payroll_input_or_time_zone.1e7fd3fe")) }
        let encodedInput = try JSONEncoder().encode(input), encodedPolicy = try JSONEncoder().encode(policy)
        defaults.set(encodedInput, forKey: "dayperkRegionalPayInput")
        defaults.set(encodedPolicy, forKey: "dayperkRegionalPolicy")
        defaults.set(region.rawValue, forKey: "dayperkPayrollRegion")
        defaults.set(timeZoneID, forKey: "dayperkWorkTimeZone")
        self.region = region; self.input = input; selectedPolicy = policy; self.timeZoneID = timeZoneID
    }
}
