import Foundation
@testable import DayPerk
import Testing

struct RegionalPayrollTests {
    @Test func hongKongUsesProgressiveOrStandardTaxAndMonthlyMPF() throws {
        let calculator = InternationalPayrollCalculator(), hk = try policy("hk-hong-kong")
        let ordinary = try calculator.estimate(input: input(360_000), policy: hk)
        #expect(ordinary.employeeContributions == 18_000 && ordinary.employerContributions == 18_000)
        #expect(ordinary.annualIncomeTax == 15_580)
        let low = try calculator.estimate(input: input(7_000 * 12), policy: hk)
        #expect(low.employeeContributions == 0 && low.employerContributions == 4200)
        var bonus = input(7_000 * 12); bonus.annualBonus = 1000
        let withBonus = try calculator.estimate(input: bonus, policy: hk)
        #expect(withBonus.employeeContributions == 400)
        let high = try calculator.estimate(input: input(6_018_000), policy: hk)
        #expect(high.annualIncomeTax == 910_000)
        var older = input(360_000); older.age = 65
        #expect(try calculator.estimate(input: older, policy: hk).employeeContributions == 0)
    }

    @Test func macauUsesItsOwnTaxDeductionReliefAndFixedSocialContributions() throws {
        let calculator = InternationalPayrollCalculator(), mo = try policy("mo-macau")
        let ordinary = try calculator.estimate(input: input(240_000), policy: mo)
        #expect(ordinary.annualIncomeTax == 1876)
        #expect(ordinary.employeeContributions == 360 && ordinary.employerContributions == 720)
        #expect(try calculator.estimate(input: input(192_000), policy: mo).annualIncomeTax == 0)
        var older = input(264_000); older.age = 65
        #expect(try calculator.estimate(input: older, policy: mo).annualIncomeTax == 0)
        #expect(try calculator.estimate(input: input(0), policy: mo).employeeContributions == 0)
        let fractional = try calculator.estimate(input: input(240_001), policy: mo)
        #expect(fractional.annualIncomeTax == 1877)
        for (region, currency, zone) in [(PayrollRegion.hongKong, "HKD", "Asia/Hong_Kong"), (.macau, "MOP", "Asia/Macau")] {
            let preset = try #require(PayrollCatalog.bundled.policies(for: region).first)
            #expect(preset.country == region && preset.currency == currency && region.currencyCode == currency)
            #expect(WorkTimeZoneOptions.cities.contains(zone))
            try preset.validate()
        }
        #expect(SupportedCurrency.mop.symbol == "MOP$")
    }

    @Test func macauCalendarCalculatesPublicDaysWithoutGovernmentOnlyLeave() throws {
        for year in [2026, 2027] {
            let days = try MacauPublicHolidays.days(year: year)
            #expect(days.count == 20 && Set(days.map(\.date)).count == 20)
            try RegionalHolidayCalendar.validate(days, country: "MO", year: year)
        }
        let year2026 = try MacauPublicHolidays.days(year: 2026)
        #expect(year2026.contains { $0.date == "2026-02-17" && $0.name == "holiday.cny1" })
        #expect(year2026.contains { $0.date == "2026-04-03" && $0.name == "Good Friday" })
        #expect(!year2026.contains { $0.date == "2026-04-06" })
        #expect(!year2026.contains { $0.date == "2026-12-31" })
        let year2027 = try MacauPublicHolidays.days(year: 2027)
        #expect(year2027.contains { $0.date == "2027-02-06" && $0.name == "holiday.cny1" })
        #expect(year2027.contains { $0.date == "2027-03-26" && $0.name == "Good Friday" })
        #expect(throws: DayPerkInputError.self) { try MacauPublicHolidays.days(year: 2028) }
        let holidays = RegionalHolidayCalendar(defaults: UserDefaults(suiteName: "calendar-hkmo-\(UUID())")!)
        #expect(holidays.days(country: "HK", subdivision: "HK").count == 34)
        #expect(holidays.days(country: "MO", subdivision: "MO").count == 40)
    }
    @Test func utcChoicesUseCompleteActualCivilOffsets() throws {
        #expect(WorkTimeZoneOptions.offsets.count == 40)
        for seconds in WorkTimeZoneOptions.offsets {
            let identifier = try #require(WorkTimeZoneOptions.fixedIdentifier(seconds))
            #expect(TimeZone(identifier: identifier)?.secondsFromGMT() == seconds)
        }
        #expect(WorkTimeZoneOptions.fixedIdentifier(-12 * 3600 - 60) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(14 * 3600 + 60) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(8 * 3600 + 1) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(-8 * 3600 - 15 * 60) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(8 * 3600 + 30 * 60) == nil)
        for zone in ["Asia/Kathmandu", "Asia/Kolkata", "Australia/Eucla", "Australia/Adelaide", "Pacific/Chatham", "America/St_Johns", "Pacific/Marquesas"] {
            for date in [Date(timeIntervalSince1970: 1_768_478_400), Date(timeIntervalSince1970: 1_784_116_800)] {
                #expect(WorkTimeZoneOptions.offsets.contains(TimeZone(identifier: zone)!.secondsFromGMT(for: date)))
            }
        }
        #expect(WorkTimeZoneOptions.label(8 * 3600) == "UTC+08:00")
        #expect(WorkTimeZoneOptions.label(5 * 3600 + 45 * 60) == "UTC+05:45")
        #expect(WorkTimeZoneOptions.label(-3 * 3600 - 30 * 60) == "UTC−03:30")
    }

    @Test func citiesKeepDaylightSavingAndExplicitUTCIsFixed() throws {
        let winter = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
        let summer = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let city = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(city.secondsFromGMT(for: winter) != city.secondsFromGMT(for: summer))
        let fixedID = try #require(WorkTimeZoneOptions.fixedIdentifier(-8 * 3600))
        let fixed = try #require(TimeZone(identifier: fixedID))
        #expect(fixed.secondsFromGMT(for: winter) == fixed.secondsFromGMT(for: summer))
        #expect(WorkTimeZoneOptions.fixedIdentifier(99 * 3600) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(15 * 60) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(44 * 60) == nil)
        #expect(WorkTimeZoneOptions.fixedIdentifier(14 * 3600 + 15 * 60) == nil)
        #expect(WorkTimeZoneOptions.cities.contains("Pacific/Auckland"))
        #expect(WorkTimeZoneOptions.cities.contains("Europe/Berlin"))
    }

    @Test func nonWholeHourUTCOffsetsSurviveSavingAndReloading() throws {
        let suite = "app.dayperk.tests.utc-minutes." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for seconds in [-9 * 3600 - 30 * 60, -3 * 3600 - 30 * 60, 5 * 3600 + 45 * 60, 8 * 3600 + 45 * 60] {
            let identifier = try #require(WorkTimeZoneOptions.fixedIdentifier(seconds))
            try RegionalPayrollSettings(defaults: defaults).save(region: .china, input: RegionalPayInput(), policy: .custom, timeZoneID: identifier)
            let restored = RegionalPayrollSettings(defaults: defaults)
            #expect(restored.timeZoneID == identifier)
            #expect(restored.calendar.timeZone.secondsFromGMT() == seconds)
        }
    }

    private func policy(_ id: String) throws -> RegionalPayrollPolicy {
        try #require(PayrollCatalog.bundled.policies.first { $0.id == id })
    }
    private func input(_ gross: Double) -> RegionalPayInput {
        var result = RegionalPayInput(); result.amount = gross; result.frequency = .annual; return result
    }
    @Test func catalogAndHolidayDataAreCompleteAndPublic() throws {
        let catalogURL = try #require(Bundle.main.url(forResource: "PayrollCatalog", withExtension: "json"))
        try JSONDecoder().decode(PayrollCatalog.self, from: Data(contentsOf: catalogURL)).validate()
        try PayrollCatalog.bundled.validate()
        #expect(PayrollCatalog.bundled.policies.count == 58)
        #expect(CityPayrollTemplates.all.count == 5)
        #expect(PayrollCatalog.bundled.policies.allSatisfy { !$0.sources.isEmpty && !$0.assumptions.isEmpty })
        let url = try #require(Bundle.main.url(forResource: "RegionalHolidays", withExtension: "json"))
        let snapshots = try JSONDecoder().decode([RegionalHolidaySnapshot].self, from: Data(contentsOf: url))
        #expect(snapshots.count == 22)
        for item in snapshots { try RegionalHolidayCalendar.validate(item.holidays, country: item.country, year: item.year) }
    }
    @Test func majorUSCitiesUseTheirOwnStateTaxesAndContributions() throws {
        let catalog = PayrollCatalog.bundled
        #expect(catalog.policies(for: .unitedStates).count >= 10)
        #expect(catalog.policies(for: .canada).count <= 6)
        let calculator = InternationalPayrollCalculator(), pay = input(11_454 * 12)
        let california = try calculator.estimate(input: pay, policy: policy("us-san-jose"))
        let sanDiego = try calculator.estimate(input: pay, policy: policy("us-san-diego"))
        #expect(sanDiego.cashNet == california.cashNet)
        #expect(california.annualRegionalTax > 0)
        for id in ["us-austin", "us-houston", "us-dallas", "us-miami"] {
            let template = try policy(id)
            let estimate = try calculator.estimate(input: pay, policy: template)
            #expect(estimate.annualIncomeTax == california.annualIncomeTax)
            #expect(estimate.annualRegionalTax == 0)
            #expect(Set(estimate.contributions.map(\.id)) == ["social-security", "medicare", "additional-medicare"])
            #expect(abs(estimate.employeeContributions - pay.annualBase * 0.0765) < 0.000001)
            #expect(estimate.cashNet > california.cashNet)
            #expect(!template.sources.isEmpty)
        }
    }

    @Test func annualResidentExamplesMatchPublishedBands() throws {
        let calculator = InternationalPayrollCalculator()
        let uk = try calculator.estimate(input: input(50_000), policy: policy("gb-london"))
        #expect(abs(uk.annualIncomeTax - 7486) < 0.01)
        #expect(abs(uk.employeeContributions - 2994.4) < 0.01)
        #expect(abs(uk.cashNet - 39519.6) < 0.01)
        let au = try calculator.estimate(input: input(100_000), policy: policy("au-sydney"))
        #expect(abs(au.annualIncomeTax - 22520) < 0.01)
        #expect(au.employerContributions == 12000)
        let us = try calculator.estimate(input: input(100_000), policy: policy("us-washington-dc"))
        #expect(us.annualIncomeTax == 13170)
        #expect(us.employeeContributions == 7650)
        let sg = try calculator.estimate(input: input(120_000), policy: policy("sg-singapore"))
        #expect(abs(sg.employeeContributions - 19200) < 0.01)
        #expect(sg.annualIncomeTax == 5627)
    }
    @Test func countryCapsAndGenericEditsApply() throws {
        let calculator = InternationalPayrollCalculator()
        let ca = try calculator.estimate(input: input(100_000), policy: policy("ca-vancouver"))
        #expect(abs(try #require(ca.contributions.first { $0.id == "cpp2" }).employee - 416) < 0.001)
        var low = input(120_000); low.declaredMonthlySocialBase = 500_000
        let kr = try calculator.estimate(input: low, policy: policy("kr-seoul"))
        #expect(abs(try #require(kr.contributions.first { $0.id == "pension" }).employee - 285_000) < 0.001)
        var jpInput = input(12_000_000); jpInput.age = 45
        let jp = try calculator.estimate(input: jpInput, policy: policy("jp-tokyo"))
        #expect(abs(try #require(jp.contributions.first { $0.id == "pension" }).employee - 713700) < 0.001)
        var custom = RegionalPayrollPolicy.custom
        custom.taxBands = [TaxBand(lower: 0, rate: 0.1), TaxBand(lower: 10_000, rate: 0.2)]
        custom.contributions = [ContributionRule(id: "fund", name: "Fund", employeeRate: 0.3, employerRate: 0.3)]
        let result = try calculator.estimate(input: input(20_000), policy: custom)
        #expect(result.annualIncomeTax == 3000 && result.cashNet == 11000)
        #expect(result.employerContributions == 6000)
    }
    @Test func newZealandIncludesKiwiSaverAndCappedACC() throws {
        let calculator = InternationalPayrollCalculator()
        var pay = input(100_000)
        let nz = try calculator.estimate(input: pay, policy: policy("nz-auckland"))
        #expect(nz.annualIncomeTax == 22877.5)
        #expect(abs(nz.employeeContributions - 5250) < 0.001)
        #expect(nz.cashNet == 71872.5)
        pay.kiwiSaverEnabled = false
        let without = try calculator.estimate(input: pay, policy: policy("nz-wellington"))
        #expect(without.annualIncomeTax == nz.annualIncomeTax)
        #expect(without.cashNet == nz.cashNet + 3500)
        pay = input(200_000)
        let capped = try calculator.estimate(input: pay, policy: policy("nz-auckland"))
        #expect(abs(try #require(capped.contributions.first { $0.id == "acc" }).employee - 2741.2175) < 0.001)
        pay = input(68_000); pay.eligibleForIETC = true
        let eligible = try calculator.estimate(input: pay, policy: policy("nz-auckland"))
        pay.eligibleForIETC = false
        let ordinary = try calculator.estimate(input: pay, policy: policy("nz-auckland"))
        #expect(ordinary.annualIncomeTax - eligible.annualIncomeTax == 260)
    }

    @Test func germanyUsesTariffFamilyDetailsAndStateCareSplit() throws {
        #expect(InternationalPayrollCalculator.germanIncomeTax(12_348) == 0)
        #expect(InternationalPayrollCalculator.germanIncomeTax(60_000) == 14_233)
        #expect(InternationalPayrollCalculator.germanIncomeTax(300_000) == 115_529)
        let calculator = InternationalPayrollCalculator()
        var pay = input(60_000)
        let single = try calculator.estimate(input: pay, policy: policy("de-berlin"))
        #expect(abs(single.employeeContributions - 13_050) < 0.01)
        pay.hasChildren = true; pay.childrenUnder25 = 2
        let parent = try calculator.estimate(input: pay, policy: policy("de-berlin"))
        #expect(single.employeeContributions - parent.employeeContributions == 510)
        let saxony = try calculator.estimate(input: pay, policy: policy("de-leipzig"))
        #expect(abs(saxony.employeeContributions - parent.employeeContributions - 300) < 0.001)
        pay.paysChurchTax = true
        let church = try calculator.estimate(input: pay, policy: policy("de-munich"))
        #expect(church.annualRegionalTax > parent.annualRegionalTax)
        #expect(throws: DayPerkInputError.self) { try calculator.estimate(input: input(12_000), policy: policy("de-berlin")) }
    }

    @Test func franceUsesCSGBasisAndSupplementaryPensionThresholds() throws {
        let calculator = InternationalPayrollCalculator()
        let below = try calculator.estimate(input: input(40_000), policy: policy("fr-paris"))
        #expect(try #require(below.contributions.first { $0.id == "cet" }).employee == 0)
        #expect(abs(try #require(below.contributions.first { $0.id == "csg-deductible" }).employee - 2672.4) < 0.001)
        #expect(below.annualIncomeTax > 0 && below.cashNet > 25_000)
        let above = try calculator.estimate(input: input(60_000), policy: policy("fr-paris"))
        #expect(try #require(above.contributions.first { $0.id == "cet" }).employee == 84)
        let alsace = try calculator.estimate(input: input(60_000), policy: policy("fr-strasbourg"))
        #expect(abs(alsace.employeeContributions - above.employeeContributions - 780) < 0.001)
        let low = try calculator.estimate(input: input(15_000), policy: policy("fr-paris"))
        #expect(low.annualIncomeTax == 0)
    }

    @Test func canadaCitiesUseTheirOwnProvincialAndQuebecRules() throws {
        let calculator = InternationalPayrollCalculator()
        #expect(PayrollCatalog.bundled.policies(for: .canada).count == 6)
        let qc = try calculator.estimate(input: input(100_000), policy: policy("ca-montreal"))
        let ab = try calculator.estimate(input: input(100_000), policy: policy("ca-calgary"))
        #expect(try #require(qc.contributions.first { $0.id == "qpip" }).employee == 430)
        #expect(abs(try #require(qc.contributions.first { $0.id == "qpp-base" }).employee - 3768.3) < 0.001)
        #expect(qc.annualIncomeTax < ab.annualIncomeTax)
        #expect(qc.annualRegionalTax > ab.annualRegionalTax)
        #expect(qc.cashNet < ab.cashNet)
        for region in [PayrollRegion.newZealand, .germany, .france] {
            for p in PayrollCatalog.bundled.policies(for: region) {
                let result = try calculator.estimate(input: input(100_000), policy: p)
                #expect(result.cashNet.isFinite && result.cashNet > 0 && result.cashNet < 100_000)
            }
        }
    }

    @Test func regionalHolidaysDistinguishStatesAndLocalAnniversaries() throws {
        let name = "DayPerk-calendar-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let calendar = RegionalHolidayCalendar(defaults: defaults)
        #expect(calendar.days(country: "FR", subdivision: "FR-67").contains { $0.date == "2026-12-26" })
        #expect(!calendar.days(country: "FR", subdivision: "FR-75").contains { $0.date == "2026-12-26" })
        #expect(calendar.days(country: "DE", subdivision: "DE-BY").contains { $0.date == "2026-01-06" })
        #expect(!calendar.days(country: "DE", subdivision: "DE-BE").contains { $0.date == "2026-01-06" })
        #expect(!calendar.days(country: "NZ", subdivision: "NZ-CAN").contains { $0.localName == "Dominion Day" })
        let common = Data(#"{"2026-01-01":"New Year"}"#.utf8)
        let local = Data(#"{"2026-01-01":"New Year","2026-12-26":"Local holiday"}"#.utf8)
        let merged = try RegionalHolidayCalendar.frenchHolidays(national: common, alsaceMoselle: local)
        #expect(merged.count == 2 && merged.last?.counties == ["FR-57", "FR-67", "FR-68"])
        #expect(throws: DayPerkInputError.self) { try RegionalHolidayCalendar.frenchHolidays(national: common, alsaceMoselle: Data("{}".utf8)) }
    }

    @Test func germanResourcesCoverCoreAndRegionalStrings() throws {
        #expect(AppLanguage.german.rawValue == "de")
        #expect(PayrollRegion.newZealand.currencyCode == "NZD")
        #expect(SupportedCurrency.nzd.symbol == "NZ$")
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        #expect(bundle.localizedString(forKey: "工资与扣除", value: nil, table: "Localizable") == "Gehalt & Abzüge")
        #expect(bundle.localizedString(forKey: "payroll.region.DE", value: nil, table: "Localizable") == "Deutschland")
        #expect(bundle.localizedString(forKey: WorkTimeZoneOptions.explanationKey, value: nil, table: "Localizable").contains("Sommerzeit"))
    }

    @Test func rejectsMalformedOrUnsupportedInputs() throws {
        var bad = RegionalPayrollPolicy.custom; bad.taxBands = [TaxBand(lower: 100, rate: 0.1), TaxBand(lower: 0, rate: 0.1)]
        #expect(throws: DayPerkInputError.self) { try bad.validate() }
        var invalid = input(.infinity)
        #expect(throws: DayPerkInputError.self) { try InternationalPayrollCalculator().estimate(input: invalid, policy: .custom) }
        invalid = input(10_000); invalid.isTaxResident = false
        #expect(throws: DayPerkInputError.self) { try InternationalPayrollCalculator().estimate(input: invalid, policy: policy("gb-london")) }
    }
    @Test func regionStoresAndHolidaysStaySeparate() throws {
        let name = "DayPerk-region-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = RegionalPayrollSettings(defaults: defaults)
        defaults.set(Data([1, 2, 3]), forKey: "dayperkWorkdayOverrides")
        try settings.save(region: .canada, input: input(100000), policy: policy("ca-vancouver"), timeZoneID: "America/Vancouver")
        settings.updateOverrides(["2026-12-26": true])
        try settings.save(region: .japan, input: input(100000), policy: policy("jp-tokyo"), timeZoneID: "Asia/Tokyo")
        #expect(settings.manualOverrides.isEmpty)
        #expect(defaults.data(forKey: "dayperkWorkdayOverrides") == Data([1, 2, 3]))
        let holidays = RegionalHolidayCalendar(defaults: defaults)
        let bc = holidays.days(country: "CA", subdivision: "CA-BC")
        #expect(!bc.isEmpty && bc.allSatisfy { $0.counties == nil || $0.counties!.contains("CA-BC") })
        #expect(holidays.overrides(country: "CA", subdivision: "CA-BC", manual: ["2026-12-25": true])["2026-12-25"] == true)
    }
}
