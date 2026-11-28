import Foundation
import AppKit
import Combine
import SwiftUI
import Testing
@testable import DayPerk

struct WorkStatusTests {
    @Test func reorderingPersistsWithoutChangingActivitiesOrBilling() throws {
        let domain = "app.dayperk.tests.status-order." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let sentinel = Data([1, 2, 3]); defaults.set(sentinel, forKey: "manualWorkTrackingV1")
        let controller = WorkStatusController(defaults: defaults)
        controller.select("busy", at: at(0))
        controller.setEnabled(true, at: at(0))
        controller.updateWorking(true, at: at(0))
        controller.updateWorking(true, at: at(5))
        try controller.remove("repetitive", at: at(5))
        let definitions = Dictionary(uniqueKeysWithValues: controller.data.definitions.map { ($0.id, $0) })
        let segments = controller.recordedSegments(at: at(5))
        var requests = 0
        controller.workingRequested = { _, _ in requests += 1 }
        #expect(controller.move("rest", to: "focus", at: at(5)))
        #expect(controller.move("busy", to: "challenging", at: at(5)))
        let expected = ["rest", "focus", "lowvalue", "meaningful", "challenging", "busy"]
        #expect(controller.data.available.map(\.id) == expected)
        #expect(Dictionary(uniqueKeysWithValues: controller.data.definitions.map { ($0.id, $0) }) == definitions)
        #expect(controller.data.enabled && controller.data.selectedID == "busy")
        #expect(controller.recordedSegments(at: at(5)) == segments)
        #expect(requests == 0 && defaults.data(forKey: "manualWorkTrackingV1") == sentinel)
        let restored = WorkStatusController(defaults: defaults)
        #expect(restored.data.available.map(\.id) == expected)
        #expect(restored.data.segments == segments)
        try restored.data.validate()
    }

    @Test func invalidOrUnchangedReordersDoNotWriteData() throws {
        let domain = "app.dayperk.tests.status-order-invalid." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let controller = WorkStatusController(defaults: defaults)
        try controller.remove("busy", at: at(0))
        let before = defaults.data(forKey: WorkStatusController.storageKey)
        for pair in [("focus", "focus"), ("missing", "rest"), ("rest", "missing"), ("busy", "rest"), ("rest", "busy")] {
            #expect(!controller.move(pair.0, to: pair.1, at: at(0)))
        }
        #expect(defaults.data(forKey: WorkStatusController.storageKey) == before)
    }

    @Test func legacyActivitiesGainAnUndeletableBreakWithoutLosingRecords() throws {
        var original = WorkStatusData()
        original.definitions.removeAll(where: \.isRest)
        original.definitions.append(WorkStatusDefinition(id: "custom-old", name: "午休前整理", colorHex: "ABC12380"))
        original.segments = [WorkStatusSegment(statusID: "custom-old", start: at(0), end: at(20))]
        let bytes = try JSONEncoder().encode(original)
        let migrated = try JSONDecoder().decode(WorkStatusData.self, from: bytes)
        #expect(migrated.definitions.contains { $0.isRest && !$0.isWorking && !$0.archived })
        #expect(migrated.definitions.filter { !$0.isRest } == original.definitions)
        #expect(migrated.segments == original.segments)
        #expect(migrated.definitions.filter { !$0.isRest }.allSatisfy { $0.isWorking })
        try migrated.validate()
        let domain = "app.dayperk.tests.rest-migration." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(bytes, forKey: WorkStatusController.storageKey)
        let controller = WorkStatusController(defaults: defaults)
        #expect(throws: DayPerkInputError.self) { try controller.remove("rest") }
        try controller.saveDefinition(id: "rest", name: "不能改名", colorHex: "00FF0080", isWorking: true)
        #expect(controller.data.definitions.first(where: \.isRest)?.name == nil)
        #expect(controller.data.definitions.first(where: \.isRest)?.isWorking == false)
    }

    @Test func activityTypesPauseBillingAndBreaksAppearUntilClockOut() throws {
        let domain = "app.dayperk.tests.duty-activity." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tracking = WorkTrackingController(defaults: defaults, calendar: calendar, observeSystem: false)
        tracking.plan = WorkPlan(ratePerSecond: 1)
        let statuses = WorkStatusController(defaults: defaults)
        var now = at(0)
        statuses.workingRequested = { enabled, date in tracking.setWorkingForStatus(enabled, at: date) }
        tracking.shouldBridgePause = { !statuses.data.enabled || statuses.data.selected.isWorking }
        let subscription = tracking.$state.sink { state in
            statuses.updateWorking(state.isWorking, onDuty: state.activeWorkday == tracking.plan.businessDayKey(now, calendar: calendar), at: now)
        }
        defer { subscription.cancel(); tracking.shutdown() }
        statuses.setEnabled(true, at: now)
        try statuses.saveDefinition(name: "午休", colorHex: "EEAA55", isWorking: false, at: now)
        let lunch = try #require(statuses.data.available.last)
        #expect(!lunch.isWorking)
        tracking.setWorking(true, at: now)
        for second in 1 ... 10 { now = at(Double(second)); tracking.checkpoint(at: now) }
        statuses.select(lunch.id, at: now)
        #expect(!tracking.state.isWorking)
        #expect(statuses.data.selectedID == lunch.id)
        for second in 11 ... 15 { now = at(Double(second)); tracking.checkpoint(at: now) }
        statuses.select("busy", at: now)
        #expect(tracking.state.isWorking)
        for second in 16 ... 25 { now = at(Double(second)); tracking.checkpoint(at: now) }
        tracking.setWorking(false, at: now)
        #expect(statuses.data.selected.isRest)
        for second in 26 ... 30 { now = at(Double(second)); tracking.checkpoint(at: now) }
        tracking.setWorking(true, at: now)
        #expect(statuses.data.selectedID == "busy")
        for second in 31 ... 35 { now = at(Double(second)); tracking.checkpoint(at: now) }
        tracking.finishToday(at: now)
        let segments = statuses.recordedSegments(at: now)
        #expect(segments.map(\.statusID) == ["focus", lunch.id, "busy", "rest", "busy"])
        #expect(segments.map(\.seconds) == [10, 5, 10, 5, 5])
        #expect(tracking.state.days.reduce(0) { $0 + $1.seconds } == 25)
        #expect(tracking.state.activeWorkday == nil)
        now = at(40); tracking.checkpoint(at: now)
        #expect(statuses.recordedSegments(at: now) == segments)
        let totals = WorkStatusReport.totals(segments, definitions: statuses.data.definitions, interval: DateInterval(start: at(0), end: at(40)))
        #expect(totals.filter { !$0.definition.isWorking }.reduce(0) { $0 + $1.seconds } == 10)
        statuses.setEnabled(false, at: now); statuses.select("focus", at: now)
        #expect(!tracking.state.isWorking)
        let restored = WorkStatusController(defaults: defaults)
        #expect(restored.data.definitions.first { $0.id == lunch.id }?.isWorking == false)
        #expect(restored.data.segments == segments)
    }

    @Test func opacityRoundTripsAndLegacyColorsStayOpaque() throws {
        #expect(NSColor(WorkStatusDefinition(id: "legacy", name: "legacy", colorHex: "ABC123").color).alphaComponent == 1)
        for alpha in [0.0, 0.25, 0.5, 0.99, 1.0] {
            let hex = WorkStatusDefinition.hex(Color(nsColor: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: alpha)))
            #expect(hex.count == (alpha == 1 ? 6 : 8))
            let definition = WorkStatusDefinition(id: "custom", name: "custom", colorHex: hex)
            let decoded = try JSONDecoder().decode(WorkStatusDefinition.self, from: JSONEncoder().encode(definition))
            #expect(abs(Double(NSColor(decoded.color).alphaComponent) - alpha) <= 1.0 / 255)
            var data = WorkStatusData(); data.definitions.append(decoded)
            try data.validate()
        }
        let transparent = WorkStatusDefinition(id: "half", name: "half", colorHex: "FF000080")
        let image = transparent.menuSwatch(selected: false)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        #expect(abs(Double(pixel.alphaComponent) - 128.0 / 255) < 0.02)
    }
    @Test func menuIconsKeepTheirOwnColorsInsteadOfUsingTemplateTint() throws {
        for (hex, red) in [("FF0000", true), ("00FF00", false)] {
            let status = WorkStatusDefinition(id: "custom", name: "custom", colorHex: hex)
            let image = status.menuSwatch(selected: false)
            #expect(!image.isTemplate)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            // 显示配置可能做色彩转换，检查红绿仍可区分，而不是要求字节完全相同。
            #expect(red ? pixel.redComponent > 0.8 && pixel.greenComponent < 0.3 : pixel.greenComponent > 0.8 && pixel.redComponent < 0.3,
                    "\(hex): \(pixel.redComponent), \(pixel.greenComponent), \(pixel.blueComponent), \(pixel.alphaComponent)")
        }
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func optionalRecordingExcludesPausesAndNeverChangesPayrollValues() throws {
        let domain = "app.dayperk.tests.status." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let sentinel = Data([1, 2, 3]); defaults.set(sentinel, forKey: "manualWorkTrackingV1")
        let statuses = WorkStatusController(defaults: defaults)
        #expect(!statuses.data.enabled)
        statuses.updateWorking(true, at: at(0))
        #expect(statuses.recordedSegments(at: at(5)).isEmpty)
        statuses.setEnabled(true, at: at(10))
        statuses.updateWorking(true, at: at(15))
        statuses.updateWorking(false, at: at(16))
        statuses.select("challenging", at: at(20))
        statuses.updateWorking(true, at: at(30))
        statuses.updateWorking(true, at: at(35))
        statuses.updateWorking(false, at: at(40))
        let segments = statuses.recordedSegments(at: at(45))
        #expect(segments.map(\.seconds) == [6, 10])
        #expect(segments.map(\.statusID) == ["focus", "challenging"])
        #expect(defaults.data(forKey: "manualWorkTrackingV1") == sentinel)
        let restored = WorkStatusController(defaults: defaults)
        #expect(restored.data.segments == segments)
        #expect(restored.recordedSegments(at: at(1000)) == segments)
    }

    @Test func disablingPreservesHistoryAndDoesNotRecordOfflineTime() throws {
        let domain = "app.dayperk.tests.status-toggle." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let statuses = WorkStatusController(defaults: defaults)
        statuses.setEnabled(true, at: at(0)); statuses.updateWorking(true, at: at(0))
        statuses.updateWorking(true, at: at(3)); statuses.setEnabled(false, at: at(4))
        statuses.updateWorking(true, at: at(100))
        #expect(statuses.recordedSegments(at: at(110)).map(\.seconds) == [4])
        statuses.setEnabled(true, at: at(120)); statuses.updateWorking(true, at: at(124))
        statuses.updateWorking(false, at: at(125))
        #expect(statuses.recordedSegments(at: at(130)).map(\.seconds) == [4, 5])
    }

    @Test func customNamesColorsArchiveAndBackupRoundTrip() throws {
        let domain = "app.dayperk.tests.status-backup." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let statuses = WorkStatusController(defaults: defaults)
        try statuses.saveDefinition(name: "내 상태 workstatus.title", colorHex: "ABC12380")
        let custom = try #require(statuses.data.available.last)
        #expect(custom.title == "내 상태 workstatus.title")
        #expect(custom.colorHex == "ABC12380")
        #expect(throws: DayPerkInputError.self) { try statuses.saveDefinition(name: " ", colorHex: "ABC123") }
        #expect(throws: DayPerkInputError.self) { try statuses.saveDefinition(name: "valid", colorHex: "#bad") }
        statuses.select(custom.id, at: at(0)); statuses.setEnabled(true, at: at(0))
        statuses.updateWorking(true, at: at(0)); statuses.updateWorking(false, at: at(4))
        try statuses.remove(custom.id, at: at(5))
        #expect(!statuses.data.available.contains { $0.id == custom.id })
        #expect(statuses.data.definitions.contains { $0.id == custom.id && $0.archived })
        let emptyImage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let archive = try AppDataBackup.create(defaults: defaults, backgroundURL: emptyImage)
        let values = try AppDataBackup.validate(archive)
        let bytes = try #require(values[WorkStatusController.storageKey] as? Data)
        let restored = try JSONDecoder().decode(WorkStatusData.self, from: bytes)
        #expect(restored == statuses.data)
        #expect(restored.segments.count == 1)
    }

    @Test func reportsClipAtBusinessDayBoundariesAndIncludeArchivedStatuses() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            c.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
        }
        let interval = WorkStatusReport.interval(containing: date(7, 12), period: .day, calendar: c, dayStartMinute: 240)
        #expect(interval.duration == 23 * 3600)
        let segment = WorkStatusSegment(statusID: "focus", start: date(7, 3, 30), end: date(7, 4, 30))
        var definitions = WorkStatusDefinition.presets; definitions[0].archived = true
        let totals = WorkStatusReport.totals([segment], definitions: definitions, interval: interval)
        #expect(totals.count == 1 && totals[0].seconds == 1800)
        for period in [WorkReportPeriod.week, .month] {
            let range = WorkStatusReport.interval(containing: date(7, 12), period: period, calendar: c, dayStartMinute: 240)
            #expect(WorkStatusReport.totals([segment], definitions: definitions, interval: range).first?.seconds == 3600)
        }
        var invalid = WorkStatusData(); invalid.segments = [segment, segment]
        #expect(throws: DayPerkInputError.self) { try invalid.validate() }
    }
}
