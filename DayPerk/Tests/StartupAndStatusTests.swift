import AppKit
@testable import DayPerk
import ServiceManagement
import Testing

struct StartupAndStatusTests {
    @Test func menuBarAmountRequiresEveryVisibilityCondition() {
        for privateMode in [false, true] {
            for locked in [false, true] {
                for working in [false, true] {
                    for hideWhenPaused in [false, true] {
                        let amount = StatusBarPresentation.amount(123, privateMode: privateMode || locked,
                            isWorking: working, hideWhenPaused: hideWhenPaused)
                        #expect(amount == (!privateMode && !locked && (working || !hideWhenPaused) ? "123" : ""))
                    }
                }
            }
        }
    }

    @MainActor @Test func sensitiveMaskSurvivesLockUnlockAndRelaunch() {
        let store = UserDefaults(suiteName: "sensitive-visibility-test-\(UUID().uuidString)")!
        let privacy = PrivacySettings(defaults: store)
        let access = SalaryAccessController(defaults: store) { _, done in done(true) }
        #expect(!privacy.isPrivacyModeEnabled)
        access.setSensitiveInformationHidden(true, privacy: privacy)
        access.setHideWhenPaused(false)
        access.lockAllData(); access.unlockAllData()
        #expect(!access.isDataLocked && access.settingsUnlocked && privacy.isPrivacyModeEnabled)
        #expect(PrivacySettings(defaults: store).isPrivacyModeEnabled && !access.hideWhenPaused)
        #expect(StatusBarPresentation.amount(123, privateMode: privacy.isPrivacyModeEnabled || access.isDataLocked).isEmpty)
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(!PrivacySettings(defaults: store).isPrivacyModeEnabled)
        #expect(StatusBarPresentation.amount(123, privateMode: privacy.isPrivacyModeEnabled) == "123")
    }

    @MainActor @Test func legacyNumberHidingMigratesOnceWithoutChangingOtherPreferences() {
        let store = UserDefaults(suiteName: "sensitive-migration-test-\(UUID().uuidString)")!
        store.set(true, forKey: "isMenuBarAmountHidden")
        store.set(true, forKey: "allDataLocked")
        store.set(false, forKey: "hideAmountWhenPaused")
        let privacy = PrivacySettings(defaults: store)
        #expect(privacy.isPrivacyModeEnabled && !store.bool(forKey: "isMenuBarAmountHidden"))
        #expect(store.bool(forKey: "allDataLocked") && !store.bool(forKey: "hideAmountWhenPaused"))
        let access = SalaryAccessController(defaults: store) { _, done in done(true) }
        access.setSensitiveInformationHidden(false, privacy: privacy)
        #expect(!PrivacySettings(defaults: store).isPrivacyModeEnabled)
    }

    @Test func overdueUsesConfiguredHoursAndIconRemainsAdaptive() {
        #expect(!StatusBarPresentation.isOverdue(seconds: 8 * 3600, referenceMinutes: 480))
        #expect(StatusBarPresentation.isOverdue(seconds: 8 * 3600 + 1, referenceMinutes: 480))
        #expect(StatusBarPresentation.isOverdue(seconds: 7 * 3600, referenceMinutes: 360))
        #expect(!StatusBarPresentation.isOverdue(seconds: .nan, referenceMinutes: 480))
        #expect(!StatusBarPresentation.isOverdue(seconds: 3600, referenceMinutes: 0))
        #expect(CoffeeStatusIcon.make(active: true).isTemplate)
        #expect(CoffeeStatusIcon.make(active: false).isTemplate)
    }

    @MainActor @Test func caffeineOnlyAddsSteamWithoutMovingTheCup() throws {
        let off = CoffeeStatusIcon.make(active: false)
        let on = CoffeeStatusIcon.make(active: true)
        #expect(off.size == on.size)

        func pixels(_ image: NSImage, scale: Int, height: Int) throws -> Data {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 24 * scale, pixelsHigh: height * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let data = try #require(bitmap.bitmapData)
            data.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let transform = NSAffineTransform()
            transform.scale(by: CGFloat(scale)); transform.concat()
            image.draw(in: NSRect(x: 0, y: 0, width: 24, height: height),
                from: NSRect(x: 0, y: 0, width: 24, height: height), operation: .copy, fraction: 1)
            return Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }

        // 分别验证普通与 Retina 栅格，杯身区域逐像素一致，热气区域才有差异。
        for scale in [1, 2, 4] {
            #expect(try pixels(off, scale: scale, height: 14) == pixels(on, scale: scale, height: 14))
            #expect(try pixels(off, scale: scale, height: 20) != pixels(on, scale: scale, height: 20))
        }
    }

    @MainActor @Test func loginRegistrationReportsApprovalAndFailureWithoutFalseEnabledState() {
        var state = SMAppService.Status.notRegistered
        let settings = LaunchAtLoginManager(readStatus: { state }, register: { state = .requiresApproval }, unregister: { state = .notRegistered })
        #expect(!settings.isEnabled && !settings.startsCaffeine)
        settings.setEnabled(true)
        #expect(settings.isEnabled && settings.needsApproval && !settings.startsCaffeine)
        state = .enabled; settings.refreshStatus()
        #expect(settings.startsCaffeine)
        settings.setEnabled(false)
        #expect(!settings.isEnabled)
        let failed = LaunchAtLoginManager(readStatus: { .notRegistered }, register: { throw CocoaError(.fileWriteNoPermission) })
        failed.setEnabled(true)
        #expect(!failed.isEnabled && !failed.errorMessage.isEmpty)
    }
}

@MainActor struct StatusItemClickTests {
    @Test func doubleClickLocksWithoutEverRunningSingleClick() async throws {
        let handler = StatusItemClickHandler(interval: 0.03)
        var events: [String] = []
        handler.handle(clickCount: 1, single: { events.append("open") }, double: { events.append("lock") })
        #expect(events.isEmpty)
        handler.handle(clickCount: 2, single: { events.append("open") }, double: { events.append("lock") })
        #expect(events == ["lock"])
        try await Task.sleep(for: .milliseconds(70))
        #expect(events == ["lock"])
    }
    @Test func secondPressCancelsSingleEvenWhenReleaseComesAfterTheInterval() async throws {
        let handler = StatusItemClickHandler(interval: 0.02)
        var events: [String] = []
        handler.handle(clickCount: 1, single: { events.append("open") }, double: { events.append("lock") })
        #expect(handler.beginPress())
        try await Task.sleep(for: .milliseconds(50))
        #expect(events.isEmpty)
        handler.handle(clickCount: 2, single: { events.append("open") }, double: { events.append("lock") })
        #expect(events == ["lock"])
    }
    @Test func slowerSecondClickIsIndependentAfterTheShortWindow() async throws {
        let handler = StatusItemClickHandler(interval: 0.02)
        var opened = 0
        #expect(!handler.beginPress())
        handler.handle(clickCount: 1, single: { opened += 1 }, double: {})
        try await Task.sleep(for: .milliseconds(50))
        #expect(opened == 1 && !handler.beginPress())
    }
    @Test func singleClickRunsOnceAndOtherClicksCancelPendingOpen() async throws {
        let handler = StatusItemClickHandler(interval: 0.02)
        var opens = 0
        handler.handle(clickCount: 1, single: { opens += 1 }, double: {})
        try await Task.sleep(for: .milliseconds(50))
        #expect(opens == 1)
        handler.handle(clickCount: 1, single: { opens += 1 }, double: {})
        handler.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(opens == 1)
        handler.handle(clickCount: 3, single: { opens += 1 }, double: {})
        try await Task.sleep(for: .milliseconds(50))
        #expect(opens == 1)
    }
}
