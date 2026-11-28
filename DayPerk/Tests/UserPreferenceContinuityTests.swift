import AppKit
import Foundation
import Testing
@testable import DayPerk

struct UserPreferenceContinuityTests {
    @Test func changingPresetAppearanceKeepsItsLocalizedNameAndPreservesCustomNames() throws {
        let defaults = UserDefaults(suiteName: "app.dayperk.tests.preset-name." + UUID().uuidString)!
        let controller = WorkStatusController(defaults: defaults)
        let preset = try #require(controller.data.available.first { $0.id == "challenging" })
        try controller.saveDefinition(id: preset.id, name: preset.title, colorHex: "12345680", isWorking: false)
        let updated = try #require(controller.data.definitions.first { $0.id == preset.id })
        #expect(updated.name == nil && updated.colorHex == "12345680" && !updated.isWorking)
        try controller.saveDefinition(id: preset.id, name: "我的站会", colorHex: "654321", isWorking: true)
        let renamed = try #require(controller.data.available.first { $0.id == preset.id })
        try controller.saveDefinition(id: renamed.id, name: renamed.title, colorHex: "ABCDEF")
        #expect(WorkStatusController(defaults: defaults).data.available.first { $0.id == preset.id }?.name == "我的站会")
        let localization = LocalizationManager.shared
        for language in AppLanguage.allCases where language != .system {
            for definition in WorkStatusDefinition.presets {
                let key = "workstatus.preset." + definition.id
                let translated = localization.string(for: key, language: language.rawValue)
                #expect(translated != key)
                var legacy = definition; legacy.name = translated
                #expect(legacy.usesPresetName && legacy.title == L10n.text(key))
            }
        }
        #expect(!WorkStatusDefinition(id: "challenging", name: "我的站会", colorHex: "ABCDEF").usesPresetName)
    }

    @Test func backupIntoAFreshStoreKeepsStatusesHistoryThemeLanguageAndBackground() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dayperk-continuity-" + UUID().uuidString)
        let source = UserDataStore(directory: directory.appendingPathComponent("source"))
        let target = UserDataStore(directory: directory.appendingPathComponent("target"))
        let sourceImage = directory.appendingPathComponent("source.png"), targetImage = directory.appendingPathComponent("target.png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        try image.write(to: sourceImage)
        let statuses = WorkStatusController(defaults: source)
        statuses.setEnabled(true)
        try statuses.remove("busy")
        try statuses.saveDefinition(name: "午休", colorHex: "FFAA3380", isWorking: false)
        let lunch = try #require(statuses.data.available.last)
        statuses.select(lunch.id)
        statuses.move("rest", to: "focus")
        let start = Date(timeIntervalSince1970: 1_000_000)
        statuses.updateWorking(false, onDuty: true, at: start)
        statuses.updateWorking(false, onDuty: true, at: start.addingTimeInterval(5))
        statuses.checkpoint(at: start.addingTimeInterval(5))
        var state = WorkTrackingState()
        state.days = [WorkDayTotal(id: "2026-11-24", seconds: 23400, earned: 1234, referenceSeconds: 28800)]
        source.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        source.set("fr", forKey: "appLanguage")
        source.set(BrewTheme.purple.rawValue, forKey: "brewTheme")
        let background = BackgroundPreferences(enabled: true, dimming: 0.45,
            windowCrop: BackgroundCrop(x: 0.2, y: 0.8, zoom: 1.8), panelCrop: BackgroundCrop(x: 0.6, y: 0.3, zoom: 2))
        source.set(try JSONEncoder().encode(background), forKey: "brewBackground")
        var rhythm = WorkRhythm()
        rhythm.scheduleRules = [WorkScheduleRule(name: "周五", weekdays: [6], schedule: DayWorkSchedule())]
        source.set(try JSONEncoder().encode(rhythm), forKey: "dayperkWorkRhythm")
        let expectedStatuses = try #require(source.data(forKey: WorkStatusController.storageKey))
        let archive = try JSONDecoder().decode(AppDataArchive.self, from: AppDataBackup.encoded(AppDataBackup.create(defaults: source, backgroundURL: sourceImage)))
        try AppDataBackup.restore(archive, defaults: target, backgroundURL: targetImage)
        #expect(target.data(forKey: WorkStatusController.storageKey) == expectedStatuses)
        #expect(target.data(forKey: "manualWorkTrackingV1") == source.data(forKey: "manualWorkTrackingV1"))
        #expect(target.data(forKey: "dayperkWorkRhythm") == source.data(forKey: "dayperkWorkRhythm"))
        #expect(target.string(forKey: "appLanguage") == "fr")
        let appearance = AppearanceSettings(defaults: target, imageURL: targetImage)
        #expect(appearance.theme == .purple && appearance.background == background && appearance.backgroundImage != nil)
        #expect(try Data(contentsOf: targetImage) == image)
        let restarted = WorkStatusController(defaults: UserDataStore(directory: directory.appendingPathComponent("target")))
        #expect(restarted.data.available.map(\.id) == statuses.data.available.map(\.id))
        #expect(!restarted.data.available.contains { $0.id == "busy" })
        #expect(restarted.data.definitions.first { $0.id == "busy" }?.archived == true)
        #expect(restarted.data.segments.count == 1 && restarted.data.segments[0].statusID == lunch.id)
    }
}
