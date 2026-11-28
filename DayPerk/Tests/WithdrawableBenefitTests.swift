import Foundation
@testable import DayPerk
import Testing

struct WithdrawableBenefitTests {
    @Test func multipleItemsKeepIndependentChoicesAcrossReopenAndCurrencyChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("benefit-list-" + UUID().uuidString)
        let store = UserDataStore(directory: folder)
        let settings = RegionalPayrollSettings(defaults: store)
        let first = WithdrawableBenefit(name: "Available savings", monthlyAmount: 500, showInEstimate: false)
        let second = WithdrawableBenefit(name: "Monthly withdrawal", monthlyAmount: 120, includeInRate: false)
        try settings.saveBenefits([first, second], region: .singapore, currency: "SGD")
        try settings.saveBenefits([WithdrawableBenefit(name: "Other currency", monthlyAmount: 15)], region: .singapore, currency: "USD")
        let reopened = RegionalPayrollSettings(defaults: UserDataStore(directory: folder))
        #expect(reopened.withdrawableBenefits(region: .singapore, currency: "SGD") == [first, second])
        #expect(reopened.withdrawableBenefits(region: .singapore, currency: "USD").first?.monthlyAmount == 15)
        #expect(reopened.withdrawableBenefits(region: .unitedStates, currency: "USD").isEmpty)
        let pay = RegionalPayEstimate(annualGross: 120000, annualIncomeTax: 20000, annualRegionalTax: 0,
            contributions: [PayrollAmountLine(id: "retirement", name: "Retirement", employee: 10000, employer: 20000)])
        #expect(pay.monthlyTimeValueBasis(deduct: true, benefits: [first, second]) == 8000)
        let shown = [first, second].filter(\.showInEstimate).reduce(0.0) { $0 + $1.monthlyAmount }
        #expect(shown == 120)
        try settings.saveBenefits([], region: .singapore, currency: "SGD")
        #expect(RegionalPayrollSettings(defaults: UserDataStore(directory: folder)).withdrawableBenefits(region: .singapore, currency: "SGD").isEmpty)
    }

    @Test func oldSingleBenefitAndHousingFundSelectionsArePreserved() throws {
        let store = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("benefit-migration-" + UUID().uuidString))
        let old = Data(#"{"SG:SGD":{"name":"My savings","monthlyAmount":250,"includeInRate":false,"showInEstimate":true}}"#.utf8)
        store.set(old, forKey: "dayperkWithdrawableBenefits")
        store.set(true, forKey: "includeHousingFundInRate")
        store.set(false, forKey: "includeHousingFundInEstimate")
        let settings = RegionalPayrollSettings(defaults: store)
        let migrated = settings.withdrawableBenefits(region: .singapore, currency: "SGD")
        #expect(migrated.count == 1 && migrated[0].id == "legacy" && migrated[0].monthlyAmount == 250)
        #expect(!migrated[0].includeInRate && migrated[0].showInEstimate)
        #expect(settings.withdrawableBenefits(region: .china, currency: "CNY").isEmpty)
        try settings.migrateHousingFundIncome(monthlyAmount: 900, currency: "CNY")
        let fund = try #require(settings.withdrawableBenefits(region: .china, currency: "CNY").first)
        #expect(!fund.usesHousingFundAmount && fund.monthlyAmount == 900 && fund.includeInRate && !fund.showInEstimate)
        try settings.migrateHousingFundIncome(monthlyAmount: 1_800, currency: "CNY")
        #expect(settings.withdrawableBenefits(region: .china, currency: "CNY") == [fund])
        try settings.saveBenefits([fund, .init(name: "Another item", monthlyAmount: 50)], region: .china, currency: "CNY")
        let persisted = settings.withdrawableBenefits(region: .china, currency: "CNY")
        #expect(persisted.count == 2 && persisted[0].monthlyAmount == 900 && persisted[0].includeInRate && !persisted[0].showInEstimate)
        #expect(store.bool(forKey: "includeHousingFundInRate") && !store.bool(forKey: "includeHousingFundInEstimate"))
        #expect(settings.withdrawableBenefits(region: .singapore, currency: "SGD") == migrated)
        try settings.saveBenefits([], region: .china, currency: "CNY")
        try settings.migrateHousingFundIncome(monthlyAmount: 1_800, currency: "CNY")
        #expect(settings.withdrawableBenefits(region: .china, currency: "CNY").isEmpty)
    }

    @Test func newInstallsHaveNoAutomaticWithdrawalAndStoredLinkedItemsBecomeFixedIncome() throws {
        let store = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("fixed-fund-income-" + UUID().uuidString))
        let fresh = RegionalPayrollSettings(defaults: store)
        try fresh.migrateHousingFundIncome(monthlyAmount: 8_000, currency: "CNY")
        #expect(fresh.withdrawableBenefits(region: .china, currency: "CNY").isEmpty)
        let legacy = WithdrawableBenefit(id: "housing-fund", name: "原配置提取", includeInRate: false, usesHousingFundAmount: true)
        let grant = WithdrawableBenefit(name: "人才补贴", monthlyAmount: 500)
        store.set(try JSONEncoder().encode(["CN:CNY": [legacy, grant]]), forKey: "dayperkWithdrawableBenefitsV2")
        let restored = RegionalPayrollSettings(defaults: store)
        try restored.migrateHousingFundIncome(monthlyAmount: 900, currency: "CNY")
        let first = restored.withdrawableBenefits(region: .china, currency: "CNY")
        #expect(first.count == 2 && first[0].id == legacy.id && first[0].name == legacy.name)
        #expect(first[0].monthlyAmount == 900 && !first[0].usesHousingFundAmount && !first[0].includeInRate && first[0].showInEstimate)
        #expect(first[1] == grant)
        try restored.migrateHousingFundIncome(monthlyAmount: 1_800, currency: "CNY")
        #expect(restored.withdrawableBenefits(region: .china, currency: "CNY") == first)
        #expect(RegionalPayrollSettings(defaults: UserDataStore(directory: store.directory)).withdrawableBenefits(region: .china, currency: "CNY") == first)
    }

    @Test func invalidOrCorruptListsCannotOverwriteSavedChoices() throws {
        let store = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("benefit-corrupt-" + UUID().uuidString))
        let item = WithdrawableBenefit(name: "Savings", monthlyAmount: 100)
        let settings = RegionalPayrollSettings(defaults: store)
        #expect(throws: DayPerkInputError.self) { try settings.saveBenefits([item, item], region: .singapore, currency: "SGD") }
        #expect(throws: DayPerkInputError.self) { try settings.saveBenefits([.init(usesHousingFundAmount: true)], region: .singapore, currency: "SGD") }
        let corrupt = Data("invalid json".utf8)
        store.set(corrupt, forKey: "dayperkWithdrawableBenefitsV2")
        let reopened = RegionalPayrollSettings(defaults: store)
        #expect(reopened.benefitStorageError != nil)
        #expect(throws: (any Error).self) { try reopened.saveBenefits([item], region: .singapore, currency: "SGD") }
        #expect(store.data(forKey: "dayperkWithdrawableBenefitsV2") == corrupt)
    }

    @Test func customBenefitLabelsNeverFollowInterfaceTranslation() {
        for name in ["공제회 인출", "Housing fund", "公积金", "Épargne disponible", "個人積立の引出し"] {
            let row = HelpFormulaRow(amount: "+ 100", label: name, isUserProvidedLabel: true)
            #expect(row.resolvedLabel(translate: { _ in "translated" }) == name)
        }
        #expect(HelpFormulaRow(amount: "+ 100", label: "公积金").resolvedLabel(translate: { _ in "translated" }) == "translated")
    }
    @Test func benefitIsIndependentPerRegionAndCurrency() throws {
        let suite = "DayPerk-benefit-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RegionalPayrollSettings(defaults: defaults)
        let singapore = try #require(PayrollCatalog.bundled.policies(for: .singapore).first)
        try settings.save(region: .singapore, input: RegionalPayInput(), policy: singapore, timeZoneID: "Asia/Singapore")
        let value = WithdrawableBenefit(name: "Flexible savings", monthlyAmount: 1234.56, includeInRate: false)
        try settings.saveBenefit(value)
        #expect(settings.benefit == value)
        #expect(RegionalPayrollSettings(defaults: defaults).benefit == value)
        #expect(!settings.benefit(region: .unitedStates, currency: "USD").isConfigured)
        #expect(!settings.benefit(region: .singapore, currency: "EUR").isConfigured)
        #expect(!settings.benefit.includeInRate && settings.benefit.showInEstimate)
    }
    @Test func onlyConfiguredWithdrawalsIncreaseValueAndDoNotChangeTaxes() {
        let pay = RegionalPayEstimate(annualGross: 120000, annualIncomeTax: 20000, annualRegionalTax: 0,
            contributions: [PayrollAmountLine(id: "retirement", name: "Retirement", employee: 10000, employer: 20000)])
        #expect(pay.monthlyTimeValueBasis(deduct: true, benefit: WithdrawableBenefit()) == 7500)
        let value = WithdrawableBenefit(name: "Available savings", monthlyAmount: 500)
        #expect(pay.monthlyTimeValueBasis(deduct: true, benefit: value) == 8000)
        #expect(pay.monthlyTimeValueBasis(deduct: false, benefit: value) == 10500)
        var disabled = value; disabled.includeInRate = false
        #expect(pay.monthlyTimeValueBasis(deduct: true, benefit: disabled) == 7500)
        #expect(pay.annualIncomeTax == 20000 && pay.employerContributions == 20000)
    }

    @Test func benefitRequiresANameAndFiniteAmount() throws {
        for value in [WithdrawableBenefit(name: "", monthlyAmount: 50), .init(name: "Savings", monthlyAmount: -1), .init(name: "Savings", monthlyAmount: .infinity)] {
            #expect(throws: DayPerkInputError.self) { try value.validate() }
        }
        try WithdrawableBenefit().validate()
        try WithdrawableBenefit(name: "My retirement withdrawal", monthlyAmount: 1234.56).validate()
    }
}
