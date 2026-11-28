import AppKit
import Foundation
import Testing
@testable import DayPerk

struct DisplayResetAndDefaultsTests {
    @Test func newConfigurationOnlyEnablesAccidentalTapProtection() {
        let rules = WorkAutomationRules()
        #expect(!WorkPlan().linkCaffeine)
        #expect(!rules.caffeineStartsWork && !rules.caffeineStopsWork && !rules.caffeineBuffer)
        #expect(!rules.lockPausesWork && !rules.unlockStartsWork)
        #expect(!rules.pauseOnSystemLock && !rules.caffeineOffOnSystemLock)
        #expect(rules.discardShortSessions && rules.bridgeShortPauses)
    }

    @Test func appearanceResetPreservesImageBackupAndUnrelatedPreferences() throws {
        let name = "app.dayperk.tests.display." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(11454, forKey: "dayperkBaseSalary")
        defaults.set(Data([1, 2, 3]), forKey: "dayperkLeaveDays")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("background.png")
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(image.representation(using: .png, properties: [:])); try bytes.write(to: url)
        let settings = AppearanceSettings(defaults: defaults, imageURL: url)
        settings.select(.rose); settings.updateBackground(BackgroundPreferences(enabled: true, dimming: 0.7))
        try settings.resetToDefaults()
        #expect(settings.theme == .cyan && settings.background == BackgroundPreferences())
        #expect(settings.backgroundImage == nil && !FileManager.default.fileExists(atPath: url.path))
        let backup = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("background-before-reset-") })
        #expect(try Data(contentsOf: backup) == bytes)
        #expect(AppearanceSettings(defaults: defaults, imageURL: url).backgroundImage == nil)
        #expect(defaults.integer(forKey: "dayperkBaseSalary") == 11454)
        #expect(defaults.data(forKey: "dayperkLeaveDays") == Data([1, 2, 3]))
    }

    @MainActor @Test func resetCannotRevealHiddenPayWhenAuthenticationIsCancelled() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.reset-denied." + UUID().uuidString))
        defaults.set(true, forKey: "isPrivacyModeEnabled")
        let privacy = PrivacySettings(defaults: defaults)
        var requested = 0; var reset = false
        let access = SalaryAccessController(defaults: defaults) { _, done in requested += 1; done(false) }
        access.resetDisplayPreferences(privacy: privacy, reset: { reset = true }, completion: { _ in })
        #expect(requested == 1 && !reset && privacy.isPrivacyModeEnabled)
    }

    @MainActor @Test func successfulResetRestoresProtectionWithoutChangingLockOrLedger() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.reset-allowed." + UUID().uuidString))
        defaults.set(true, forKey: "isPrivacyModeEnabled")
        defaults.set(false, forKey: "salaryDashboardProtected"); defaults.set(false, forKey: "hideAmountWhenPaused")
        defaults.set("ledger", forKey: "manualWorkTrackingV1")
        let privacy = PrivacySettings(defaults: defaults)
        var requested = 0; var completed = false
        let access = SalaryAccessController(defaults: defaults) { _, done in requested += 1; done(true) }
        access.unlockSettings()
        access.resetDisplayPreferences(privacy: privacy, reset: {}, completion: { completed = $0 == nil })
        #expect(requested == 2 && completed && !privacy.isPrivacyModeEnabled)
        #expect(access.dashboardProtected && access.hideWhenPaused && !access.settingsUnlocked)
        #expect(!access.isDataLocked && defaults.string(forKey: "manualWorkTrackingV1") == "ledger")
    }
}
