import Foundation

struct HolidayProviderConfiguration: Codable {
    var country: String
    var kind: String
    var url: String
    var officialURL: String
}

struct PayrollCatalog: Codable {
    var version: Int
    var updated: String
    var policies: [RegionalPayrollPolicy]
    var mainlandChinaCities: [CityPayrollTemplate]
    var holidayProviders: [HolidayProviderConfiguration]

    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "PayrollCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Self.self, from: data),
              (try? catalog.validate()) != nil else { return Self(version: 1, updated: "", policies: [], mainlandChinaCities: [], holidayProviders: []) }
        return catalog
    }()

    func validate() throws {
        guard version == 1, Set(policies.map(\.id)).count == policies.count else { throw DayPerkInputError(message: L10n.text("ui.invalid_policy_catalog.1971a1cb")) }
        guard mainlandChinaCities.count == 5, Set(mainlandChinaCities.map(\.id)).count == 5,
              mainlandChinaCities.allSatisfy({ !$0.sources.isEmpty && $0.values.values.allSatisfy { $0.isFinite && $0 >= 0 } }) else { throw DayPerkInputError(message: L10n.text("ui.invalid_mainland_china_city_presets.7baedc3a")) }
        for policy in policies { try policy.validate() }
    }

    func policies(for region: PayrollRegion) -> [RegionalPayrollPolicy] { policies.filter { $0.country == region } }
}
