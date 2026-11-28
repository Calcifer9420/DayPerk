import Foundation
import Testing
@testable import DayPerk

@MainActor struct AuthorizationValidityTests {
    private func store() -> UserDefaults { UserDefaults(suiteName: "app.dayperk.tests.validity." + UUID().uuidString)! }

    @Test func durationAcceptsHoursMinutesAndSecondsWithoutGrantingAccess() throws {
        let defaults = store()
        let access = SalaryAccessController(defaults: defaults)
        #expect(access.authorizationDuration == 600 && !access.settingsUnlocked)
        #expect(try SalaryAccessController.parseDuration("01:02:03") == 3723)
        #expect(try SalaryAccessController.parseDuration("00:00:01") == 1)
        #expect(try SalaryAccessController.parseDuration("9999:59:59") == SalaryAccessController.maximumDuration)
        for input in ["", "00:00:00", "00:60:00", "00:00:60", "-1:00:00", "1:2", "10000:00:00", "a:b:c"] {
            #expect(throws: DayPerkInputError.self) { try SalaryAccessController.parseDuration(input) }
        }
        try access.setAuthorizationDuration(3723)
        #expect(!access.settingsUnlocked)
        #expect(SalaryAccessController(defaults: defaults).authorizationDuration == 3723)
        #expect(throws: DayPerkInputError.self) { try access.setAuthorizationDuration(-1) }
        #expect(access.authorizationDuration == 3723)
    }

    @Test func customDeadlineIsSharedByDetailsSettingsAndTransfers() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0; var transfers = 0
        let defaults = store()
        let access = SalaryAccessController(defaults: defaults, now: { clock }) { _, done in calls += 1; done(true) }
        try access.setAuthorizationDuration(90)
        access.unlockIncomeDetails()
        clock += 89
        access.unlockSettings(); access.authorizeDataTransfer { transfers += 1 }
        #expect(access.settingsUnlocked && access.canViewIncomeDetails && calls == 1 && transfers == 1)
        clock += 1
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
        access.authorizeDataTransfer { transfers += 1 }
        #expect(calls == 2 && transfers == 2)
        #expect(!SalaryAccessController(defaults: defaults).settingsUnlocked)
    }

    @Test func manualGrantLastsForThisRunButRestartRequiresAuthentication() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let defaults = store()
        let access = SalaryAccessController(defaults: defaults, now: { clock }) { _, done in done(true) }
        try access.setAuthorizationDuration(0)
        #expect(!access.settingsUnlocked)
        access.unlockSettings()
        clock += 100 * 365 * 86400
        access.handleSystemInterruption()
        #expect(access.settingsUnlocked && access.canViewIncomeDetails)
        let restarted = SalaryAccessController(defaults: defaults, now: { clock })
        #expect(!restarted.settingsUnlocked && !restarted.canViewIncomeDetails)
        access.revokeAuthorization()
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
        #expect(!SalaryAccessController(defaults: defaults, now: { clock }).settingsUnlocked)
    }

    @Test func failedOrCancelledAuthenticationCannotPersistAManualGrant() throws {
        let defaults = store()
        var reply: ((Bool) -> Void)?
        let access = SalaryAccessController(defaults: defaults, authenticate: { _, completion in reply = completion })
        try access.setAuthorizationDuration(0)
        access.unlockSettings(); reply?(false)
        #expect(!access.settingsUnlocked && !SalaryAccessController(defaults: defaults).settingsUnlocked)
        access.unlockSettings(); access.lockAllData(); reply?(true)
        #expect(access.isDataLocked && !access.settingsUnlocked)
        let restarted = SalaryAccessController(defaults: defaults)
        #expect(restarted.isDataLocked && !restarted.settingsUnlocked)
    }

    @Test func changingPreferenceDoesNotExtendAnExistingTimedGrant() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let access = SalaryAccessController(defaults: store(), now: { clock }) { _, done in done(true) }
        try access.setAuthorizationDuration(2)
        access.unlockSettings()
        try access.setAuthorizationDuration(0)
        clock += 2
        #expect(!access.settingsUnlocked)
        access.unlockSettings()
        clock += 86400
        #expect(access.settingsUnlocked)
        access.lockAllData()
        #expect(!access.settingsUnlocked && !access.canViewIncomeDetails)
    }

    @Test func backupCarriesLifetimePreferenceButNeverTheVerifiedGrant() throws {
        let source = store()
        let access = SalaryAccessController(defaults: source, authenticate: { _, done in done(true) })
        try access.setAuthorizationDuration(0); access.unlockSettings()
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let archive = try AppDataBackup.create(defaults: source, backgroundURL: imageURL)
        let values = try AppDataBackup.validate(archive)
        #expect(values[SalaryAccessController.durationKey] as? Int == 0)
        #expect(Set(values.keys) == [SalaryAccessController.durationKey])
        let target = UserDataStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("validity-import-" + UUID().uuidString))
        try AppDataBackup.restore(archive, defaults: target, backgroundURL: imageURL)
        let restored = SalaryAccessController(defaults: target)
        #expect(restored.authorizationDuration == 0 && !restored.settingsUnlocked)
    }

    @Test func resettingDisplayPreferencesRestoresTheDefaultValidityAndLocksAccess() throws {
        let defaults = store()
        let access = SalaryAccessController(defaults: defaults, authenticate: { _, completion in completion(true) })
        let privacy = PrivacySettings(defaults: defaults)
        try access.setAuthorizationDuration(0); access.unlockSettings()
        var completed = false
        access.resetDisplayPreferences(privacy: privacy, reset: {}) { error in completed = error == nil }
        #expect(completed && access.authorizationDuration == 600 && !access.settingsUnlocked)
        #expect(SalaryAccessController(defaults: defaults).authorizationDuration == 600)
    }
}
