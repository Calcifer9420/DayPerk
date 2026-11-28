import AppKit
import Foundation
import Testing
@testable import DayPerk

struct UserDataStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dayperk-storage-" + UUID().uuidString)
    }

    @Test func migrationKeepsOriginalAndDoesNotReimportOldSettings() throws {
        let legacy = try #require(UserDefaults(suiteName: "app.dayperk.tests.migration." + UUID().uuidString))
        legacy.set(114_514, forKey: "dayperkBaseSalary")
        legacy.set("zh-Hans", forKey: "appLanguage")
        legacy.set("private", forKey: "unrelatedCredential")
        let folder = directory()
        let first = UserDataStore(directory: folder, legacy: legacy)
        #expect(first.readError == nil)
        #expect(first.double(forKey: "dayperkBaseSalary") == 114_514)
        #expect(first.object(forKey: "unrelatedCredential") == nil)
        first.set(120_000, forKey: "dayperkBaseSalary")
        let reopened = UserDataStore(directory: folder, legacy: legacy)
        #expect(reopened.double(forKey: "dayperkBaseSalary") == 120_000)
        #expect(legacy.double(forKey: "dayperkBaseSalary") == 114_514)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("settings.plist").path))
    }

    @MainActor @Test func exportedFileRestoresSettingsLedgersLeaveAndBackgroundAfterReopening() throws {
        let folder = directory(), restoredFolder = directory()
        let source = UserDataStore(directory: folder)
        let imageURL = folder.appendingPathComponent("Appearance/background.png")
        let appearance = AppearanceSettings(defaults: source, imageURL: imageURL)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: imageURL)
        appearance.select(.purple)
        source.set("de", forKey: "appLanguage")
        source.set(114_514, forKey: "dayperkBaseSalary")
        source.set("SG", forKey: "dayperkPayrollRegion")
        source.set("Asia/Singapore", forKey: "dayperkWorkTimeZone")
        source.set(true, forKey: "hideAmountWhenPaused")
        source.set(2, forKey: "amountDecimalPlaces")
        let policy = try #require(PayrollCatalog.bundled.policies.first { $0.id == "sg-singapore" })
        var input = RegionalPayInput(); input.amount = 114_514; input.cpfStatus = "foreigner"
        source.set(try JSONEncoder().encode(input), forKey: "dayperkRegionalPayInput")
        source.set(try JSONEncoder().encode(policy), forKey: "dayperkRegionalPolicy")
        source.set(try JSONEncoder().encode(WorkAutomationRules()), forKey: "dayperkAutomationRules")
        var rhythm = WorkRhythm()
        rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6]), WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02")]
        source.set(try JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
        let benefits = [WithdrawableBenefit(name: "Savings withdrawal", monthlyAmount: 120, includeInRate: false),
            WithdrawableBenefit(name: "Available allowance", monthlyAmount: 80, showInEstimate: false)]
        try RegionalPayrollSettings(defaults: source).saveBenefits(benefits, region: .singapore, currency: "SGD")
        var state = WorkTrackingState()
        state.days = [WorkDayTotal(id: "2026-11-24", seconds: 18_000, earned: 800, ratePerSecond: 800 / 18_000, expectedIncome: 1200, currencyCode: "SGD")]
        source.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        var statuses = WorkStatusData(); statuses.enabled = true
        statuses.definitions.append(WorkStatusDefinition(id: UUID().uuidString, name: "회의", colorHex: "33BBDD80"))
        source.set(try JSONEncoder().encode(statuses), forKey: WorkStatusController.storageKey)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        let request = LeaveRequest(base: LeaveRange(start: day, end: day))
        source.set(try JSONEncoder().encode([request]), forKey: LeaveRequests.storageKey)
        let archive = try AppDataBackup.create(defaults: source, backgroundURL: imageURL)
        let export = folder.appendingPathComponent("verification.dayperk.json")
        try AppDataBackup.encoded(archive).write(to: export, options: .atomic)
        let imported = try AppDataBackup.read(export)
        let target = UserDataStore(directory: restoredFolder)
        target.set(1, forKey: "dayperkBaseSalary"); target.set(true, forKey: "dayperkLinkCaffeine")
        let restoredImage = restoredFolder.appendingPathComponent("Appearance/background.png")
        try AppDataBackup.restore(imported, defaults: target, backgroundURL: restoredImage)
        let reopened = UserDataStore(directory: restoredFolder)
        let before = try AppDataBackup.validate(archive)
        let after = try AppDataBackup.validate(AppDataBackup.create(defaults: reopened, backgroundURL: restoredImage))
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
        #expect(try Data(contentsOf: restoredImage) == png)
        #expect(reopened.object(forKey: "dayperkLinkCaffeine") == nil)
        #expect(RegionalPayrollSettings(defaults: reopened).input == input)
        #expect(RegionalPayrollSettings(defaults: reopened).withdrawableBenefits(region: .singapore, currency: "SGD") == benefits)
        #expect(try JSONDecoder().decode(WorkRhythm.self, from: #require(reopened.data(forKey: "dayperkWorkRhythm"))) == rhythm)
        #expect(!LocalPreviewMode.requiresInitialSeed(defaults: reopened, bundleID: LocalPreviewMode.bundleIdentifier))
        #expect(WorkStatusController(defaults: reopened).data == statuses)
        #expect(AppearanceSettings(defaults: reopened, imageURL: restoredImage).theme == .purple)
    }

    @Test func corruptStoreIsNeverOverwrittenWithDefaults() throws {
        let folder = directory(); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.plist"), original = Data("corrupt".utf8)
        try original.write(to: file)
        let store = UserDataStore(directory: folder)
        #expect(store.readError != nil)
        #expect(throws: (any Error).self) { try store.replace(with: ["dayperkBaseSalary": 0]) }
        #expect(try Data(contentsOf: file) == original)
        #expect(throws: (any Error).self) { try store.persist(["appLanguage": "en"]) }
        #expect(store.object(forKey: "appLanguage") == nil)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func previewSeedsOnlyAnEntirelyEmptyStoreAndNeverReplacesPreferences() throws {
        let folder = directory(), store = UserDataStore(directory: folder)
        #expect(LocalPreviewMode.requiresInitialSeed(defaults: store, bundleID: LocalPreviewMode.bundleIdentifier))
        #expect(!LocalPreviewMode.requiresInitialSeed(defaults: store, bundleID: "com.mini.Paytick.Paytick"))
        store.set("de", forKey: "appLanguage")
        #expect(!LocalPreviewMode.requiresInitialSeed(defaults: store, bundleID: LocalPreviewMode.bundleIdentifier))
        var rhythm = WorkRhythm()
        rhythm.scheduleRules = [WorkScheduleRule(weekdays: [6]), WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02")]
        try store.persist(["dayperkWorkRhythm": JSONEncoder().encode(rhythm)])
        let reopened = UserDataStore(directory: folder)
        #expect(reopened.string(forKey: "appLanguage") == "de")
        #expect(try JSONDecoder().decode(WorkRhythm.self, from: #require(reopened.data(forKey: "dayperkWorkRhythm"))) == rhythm)
        #expect(!LocalPreviewMode.requiresInitialSeed(defaults: reopened, bundleID: LocalPreviewMode.bundleIdentifier))
    }
}
