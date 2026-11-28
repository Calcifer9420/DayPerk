import Foundation
import Testing
@testable import DayPerk

struct CaliforniaExperienceTests {
    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier == "app.dayperk.documentation.california"))
    func exportCaliforniaExperience() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("LocalPreview/CaliforniaDemo", isDirectory: true)
        let values = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: directory.appendingPathComponent("source-settings.plist")), format: nil) as? [String: Any])
        try UserDataStore.shared.replace(with: values)
        var activities = try JSONDecoder().decode(WorkStatusData.self, from: #require(values[WorkStatusController.storageKey] as? Data))
        activities.enabled = true; activities.segments = []
        UserDataStore.shared.set(try JSONEncoder().encode(activities), forKey: WorkStatusController.storageKey)
        UserDataStore.shared.set(try JSONEncoder().encode(WorkTrackingState()), forKey: "manualWorkTrackingV1")
        LocalizationManager.shared.setLanguage(.chinese)
        let model = DayPerkModel()
        let policy = try #require(PayrollCatalog.bundled.policies.first { $0.id == "us-san-jose" })
        var input = RegionalPayInput(); input.amount = 114_514; input.frequency = .monthly
        try model.saveRegionalSettings(region: .unitedStates, input: input, policy: policy, timeZoneID: "America/Los_Angeles")
        let calendar = model.workCalendar, now = Date()
        let today = model.businessPlan.businessDayStart(for: now, calendar: calendar)
        var config = model.configuration
        // 演示假日加班使用明确登记，休息日不伪装成普通工作日。
        if !model.businessPlan.isWorkday(today, calendar: calendar) { config.overtimeDates[WorkPlan.dayKey(today, calendar: calendar)] = 2 }
        for offset in stride(from: -12, through: -150, by: -28) {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            if !model.businessPlan.isWorkday(date, calendar: calendar) { config.overtimeDates[WorkPlan.dayKey(date, calendar: calendar)] = 1.5 }
        }
        try model.saveConfiguration(config)
        let plan = model.businessPlan
        let working = activities.available.filter(\.isWorking)
        #expect(!working.isEmpty)
        let adjustments = [-5400, -2700, 0, 1800, 3600, 7200]
        let weights = [24, 13, 18, 12, 17, 16]
        var state = WorkTrackingState()
        for offset in -150 ... 0 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let key = WorkPlan.dayKey(date, calendar: calendar)
            guard plan.isWorkday(date, calendar: calendar), let shift = plan.scheduledInterval(for: key, calendar: calendar) else { continue }
            let reference = Int(plan.referenceSeconds(for: key))
            guard reference > 0 else { continue }
            let target = min(12 * 3600, max(1800, reference + adjustments[abs(offset) % adjustments.count]))
            var cursor = offset == -2 ? calendar.date(bySettingHour: 16, minute: 0, second: 0, of: date)! : shift.start.addingTimeInterval(offset % 4 == 0 ? -1800 : offset % 3 == 0 ? 900 : 0)
            let clockIn = cursor
            var pieces: [WorkStatusSegment] = []
            var assigned = 0
            for index in weights.indices {
                let seconds = index == weights.count - 1 ? target - assigned : target * weights[index] / 100
                assigned += seconds
                pieces.append(.init(statusID: working[(index + abs(offset)) % working.count].id, start: cursor, end: cursor.addingTimeInterval(Double(seconds))))
                cursor = cursor.addingTimeInterval(Double(seconds))
                if index == 2 {
                    pieces.append(.init(statusID: WorkStatusDefinition.rest.id, start: cursor, end: cursor.addingTimeInterval(3600)))
                    cursor = cursor.addingTimeInterval(3600)
                }
            }
            pieces = pieces.compactMap { piece in
                guard piece.start < now else { return nil }
                var value = piece; value.end = min(value.end, now)
                return value.seconds > 0 ? value : nil
            }
            guard !pieces.isEmpty else { continue }
            activities.segments += pieces
            let seconds = pieces.filter { definition in working.contains { $0.id == definition.statusID } }.reduce(0) { $0 + $1.seconds }
            state.days.append(WorkDayTotal(id: key, seconds: seconds, currencyCode: "USD", settledAt: cursor <= now ? cursor : nil,
                clockedInAt: clockIn, scheduledStart: shift.start, scheduledEnd: shift.end))
        }
        try activities.validate()
        model.tracking.shutdown()
        UserDataStore.shared.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        UserDataStore.shared.set(try JSONEncoder().encode(activities), forKey: WorkStatusController.storageKey)
        let loaded = DayPerkModel()
        loaded.refreshHistoricalData()
        #expect(loaded.regional.input.amount == 114_514 && loaded.regional.input.frequency == .monthly)
        #expect(loaded.activeCurrencyCode == "USD" && loaded.workCalendar.timeZone.identifier == "America/Los_Angeles")
        #expect(loaded.tracking.state.days.count >= 80 && activities.segments.count >= 500)
        #expect(loaded.tracking.state.days.allSatisfy { $0.seconds <= 86400 && $0.currencyCode == "USD" && $0.earned >= 0 })
        #expect(activities.segments.allSatisfy { $0.end <= now })
        let estimate = try #require(loaded.regionalEstimate)
        var income = (try? JSONDecoder().decode([RegionalIncomeRecord].self, from: values["dayperkInternationalIncomeRecords"] as? Data ?? Data())) ?? []
        for offset in 1 ... 6 {
            let date = calendar.date(byAdding: .month, value: -offset, to: today)!
            let month = String(WorkPlan.dayKey(date, calendar: calendar).prefix(7))
            income.removeAll { $0.region == .unitedStates && $0.month == month }
            income.append(.init(region: .unitedStates, currency: "USD", month: month, gross: 114_514,
                tax: (estimate.annualIncomeTax + estimate.annualRegionalTax) / 12, employeeContributions: estimate.employeeContributions / 12))
        }
        UserDataStore.shared.set(try JSONEncoder().encode(income), forKey: "dayperkInternationalIncomeRecords")
        loaded.tracking.shutdown()
        if let background = try? Data(contentsOf: directory.appendingPathComponent("background.png")) {
            try FileManager.default.createDirectory(at: AppDataBackup.backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try background.write(to: AppDataBackup.backgroundURL, options: .atomic)
        }
        let archive = try AppDataBackup.create()
        _ = try AppDataBackup.validate(archive)
        try AppDataBackup.encoded(archive).write(to: directory.appendingPathComponent("california.backup"), options: .atomic)
        try archive.preferences.write(to: directory.appendingPathComponent("california-settings.plist"), options: .atomic)
        print("California demo: \(loaded.tracking.state.days.count) days, \(activities.segments.count) activity segments, USD 114514/month")
    }
}
