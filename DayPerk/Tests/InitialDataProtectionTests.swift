import Foundation
import Testing
@testable import DayPerk

@MainActor struct InitialDataProtectionTests {
    private func store() -> UserDefaults { UserDefaults(suiteName: "app.dayperk.tests.initial-data." + UUID().uuidString)! }

    @Test func freshInstallationAndGeneratedZeroRowsDoNotNeedAuthentication() throws {
        let defaults = store()
        #expect(!SalaryDataPresence.requiresProtection(defaults: defaults))
        let tracking = WorkTrackingController(defaults: defaults, observeSystem: false)
        tracking.updatePlan(WorkPlan())
        tracking.checkpoint()
        defaults.set("fr", forKey: "appLanguage"); defaults.set("湖水蓝", forKey: "brewTheme")
        defaults.set(try JSONEncoder().encode(WorkStatusData()), forKey: WorkStatusController.storageKey)
        defaults.set(try JSONEncoder().encode(RegionalPayInput()), forKey: "dayperkRegionalPayInput")
        #expect(!SalaryDataPresence.requiresProtection(defaults: defaults))
        var prompts = 0
        let access = SalaryAccessController(defaults: defaults, allowsInitialSetup: true, authenticate: { _, done in prompts += 1; done(true) })
        access.unlockSettings(); access.unlockIncomeDetails()
        access.setDashboardProtected(false); access.setHideWhenPaused(false)
        #expect(access.settingsUnlocked && access.canViewIncomeDetails && prompts == 0)
        defaults.set(114514, forKey: "dayperkBaseSalary")
        access.revokeAuthorization(); access.unlockSettings()
        #expect(prompts == 1)
        tracking.shutdown()
    }

    @Test func recordedHoursOrSalaryRequireAuthenticationOnTheNextRun() throws {
        for key in ["dayperkBaseSalary", "manualWorkTrackingV1", "payrollIncomeRecords", "dayperkRegionalPayInput", WorkStatusController.storageKey] {
            let defaults = store()
            switch key {
            case "dayperkBaseSalary": defaults.set(114514, forKey: key)
            case "manualWorkTrackingV1":
                var state = WorkTrackingState(); state.days = [WorkDayTotal(id: "2026-11-27", seconds: 1)]
                defaults.set(try JSONEncoder().encode(state), forKey: key)
            case "payrollIncomeRecords":
                defaults.set(try JSONEncoder().encode([PayrollIncomeRecord(year: 2026, month: 11, isSalary: true, income: 0, paidTax: 0, employeeDeductions: 0)]), forKey: key)
            case "dayperkRegionalPayInput":
                var input = RegionalPayInput(); input.amount = 114514
                defaults.set(try JSONEncoder().encode(input), forKey: key)
            default:
                var data = WorkStatusData(); data.segments = [WorkStatusSegment(statusID: "focus", start: .distantPast, end: .distantPast.addingTimeInterval(1))]
                defaults.set(try JSONEncoder().encode(data), forKey: key)
            }
            #expect(SalaryDataPresence.requiresProtection(defaults: defaults))
            let access = SalaryAccessController(defaults: defaults, allowsInitialSetup: true, authenticate: { _, done in done(true) })
            #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
            access.unlockSettings()
            #expect(access.settingsUnlocked)
            #expect(!SalaryAccessController(defaults: defaults, allowsInitialSetup: true).settingsUnlocked)
        }
    }

    @Test func importedRecordsCloseSetupAndUnreadableArchivesRemainProtected() throws {
        let source = store(); source.set(114514, forKey: "dayperkBaseSalary")
        let target = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("first-import-" + UUID().uuidString))
        let initial = SalaryAccessController(defaults: target, allowsInitialSetup: true)
        #expect(initial.settingsUnlocked)
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try AppDataBackup.restore(AppDataBackup.create(defaults: source, backgroundURL: imageURL), defaults: target, backgroundURL: imageURL)
        initial.revokeAuthorization()
        let imported = SalaryAccessController(defaults: target, allowsInitialSetup: false)
        imported.lockAllData()
        #expect(imported.isDataLocked && !imported.settingsUnlocked && !imported.canViewIncomeDetails)
        let empty = store(); empty.set(true, forKey: "allDataLocked")
        #expect(SalaryAccessController(defaults: empty, allowsInitialSetup: true).settingsUnlocked)
        let damaged = store(); damaged.set(Data([1, 2, 3]), forKey: "manualWorkTrackingV1")
        #expect(SalaryDataPresence.requiresProtection(defaults: damaged))
    }
}
