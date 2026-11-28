import AppKit
import SwiftUI
import Testing
@testable import DayPerk

struct DayArrangementTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return value
    }
    private func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))! }

    @Test func makeupRequiresAnExistingRestDayOrTimeOff() {
        var plan = WorkPlan()
        #expect(!plan.canMakeupWorkday(date(23), calendar: calendar))
        #expect(plan.canMakeupWorkday(date(28), calendar: calendar))
        plan.dateOverrides["2026-11-23"] = false
        #expect(plan.canMakeupWorkday(date(23), calendar: calendar))
        plan.dateOverrides = [:]; plan.rhythm.enabled = true; plan.rhythm.cycleDays = [false]
        #expect(plan.canMakeupWorkday(date(23), calendar: calendar))
        plan.rhythm.enabled = false; plan.leaveDays["2026-11-23"] = LeaveDay(morning: .unpaid)
        #expect(plan.canMakeupWorkday(date(23), calendar: calendar))
        plan.overtimeDates["2026-11-28"] = 2
        #expect(!plan.canMakeupWorkday(date(28), calendar: calendar))
    }

    @Test func overriddenLeaveDoesNotReturnWhenAnArrangementIsRemovedOrCalendarChanges() throws {
        let original = LeaveRequest(base: LeaveRange(start: date(23), end: date(30)))
        let requests = LeaveRequests.excluding(["2026-11-23": .full, "2026-11-28": .full], from: [original], calendar: calendar)
        var plan = WorkPlan(dateOverrides: ["2026-11-28": true])
        let days = try LeaveRequests.materialize(requests, plan: plan, calendar: calendar)
        #expect(days["2026-11-23"] == nil && days["2026-11-28"] == nil)
        #expect(days["2026-11-24"]?.paidFraction == 1 && days["2026-11-30"]?.paidFraction == 1)
        plan.dateOverrides = [:]
        #expect(try LeaveRequests.materialize(requests, plan: plan, calendar: calendar)["2026-11-23"] == nil)
        let restored = try JSONDecoder().decode([LeaveRequest].self, from: JSONEncoder().encode(requests))
        #expect(restored == requests)
        var draft = LeaveRequestDraft(); draft.edit(restored[0])
        #expect(draft.request.excludedPortions == requests[0].excludedPortions)
    }

    @Test func laterHalfDayLeaveReplacesOnlyThatHalfAndKeepsTheRestOfThePeriod() throws {
        let original = LeaveRequest(base: LeaveRange(start: date(23), end: date(25), pay: .unpaid))
        let next = LeaveRequest(base: LeaveRange(start: date(24), end: date(24), portion: .morning, kind: .compensatory))
        let older = LeaveRequests.excluding(["2026-11-24": .morning], from: [original], calendar: calendar)
        let days = try LeaveRequests.materialize(older + [next], plan: WorkPlan(), calendar: calendar)
        #expect(days["2026-11-24"]?.morningKind == .compensatory)
        #expect(days["2026-11-24"]?.morning == .paid && days["2026-11-24"]?.afternoon == .unpaid)
        let removedNew = try LeaveRequests.materialize(older, plan: WorkPlan(), calendar: calendar)
        #expect(removedNew["2026-11-24"]?.morning == nil && removedNew["2026-11-24"]?.afternoon == .unpaid)
        let all = LeaveRequests.excluding(["2026-11-24": .afternoon], from: older, calendar: calendar)
        #expect(try LeaveRequests.materialize(all, plan: WorkPlan(), calendar: calendar)["2026-11-24"] == nil)
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier == "app.dayperk.documentation.calendar"))
    func dateChangesPersistWithoutResurrectingEarlierStates() throws {
        let seed = LocalPreviewMode.Seed(cityID: "hangzhou", monthlySalary: 114_514, allowance: 0, annualBonusMonths: 2, trackedHours: 6)
        try LocalPreviewMode.prepare(seed)
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        try LocalPreviewMode.apply(seed, to: model)
        defer { model.tracking.shutdown() }
        var config = model.configuration
        config.rhythm.enabled = false; config.dateOverrides = [:]; config.overtimeDates = [:]
        config.weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        try model.saveConfiguration(config)
        #expect(throws: DayPerkInputError.self) { try model.applyDayArrangement(.makeup, on: date(23)) }
        var draft = LeaveRequestDraft(); draft.base = LeaveRange(start: date(23), end: date(25), pay: .unpaid)
        try model.saveLeaveRequest(&draft, finish: true)
        try model.applyDayArrangement(.makeup, on: date(24))
        #expect(model.activeLeave(for: "2026-11-24") == nil && model.leaveDays["2026-11-24"] == nil)
        #expect(model.configuration.dateOverrides["2026-11-24"] == true && model.overtimeDates["2026-11-24"] == nil)
        try model.applyDayArrangement(.automatic, on: date(24))
        #expect(model.configuration.dateOverrides["2026-11-24"] == nil && model.leaveDays["2026-11-24"] == nil)
        #expect(model.leaveDays["2026-11-23"] != nil && model.leaveDays["2026-11-25"] != nil)
        try model.saveLeaveRequests(model.leaveRequests)
        #expect(model.leaveDays["2026-11-24"] == nil)
        var single = LeaveRequestDraft(); single.base = LeaveRange(start: date(27), end: date(27), kind: .compensatory)
        try model.saveLeaveRequest(&single, finish: true)
        try model.applyDayArrangement(.makeup, on: date(27))
        #expect(!model.leaveRequests.contains { $0.id == single.id })
        try model.applyDayArrangement(.automatic, on: date(27))
        for kind in [DayArrangement.makeup, .rest, .makeup, .automatic] { try model.applyDayArrangement(kind, on: date(28)) }
        #expect(model.configuration.dateOverrides["2026-11-28"] == nil && model.leaveDays["2026-11-28"] == nil)
        try model.applyDayArrangement(.makeup, on: date(28))
        var saturday = LeaveRequestDraft(); saturday.base = LeaveRange(start: date(28), end: date(28), kind: .compensatory)
        try model.saveLeaveRequest(&saturday, finish: true)
        #expect(model.activeLeave(for: "2026-11-28")?.isCompensatory == true)
        try model.saveLeaveRequests(model.leaveRequests.filter { $0.id != saturday.id })
        #expect(model.configuration.dateOverrides["2026-11-28"] == nil && !model.businessPlan.isScheduledWorkday(date(28), calendar: calendar))
        let loaded = UserDataStore(directory: UserDataStore.directory)
        let requests = try JSONDecoder().decode([LeaveRequest].self, from: #require(loaded.data(forKey: LeaveRequests.storageKey)))
        #expect(try LeaveRequests.materialize(requests, plan: model.businessPlan, calendar: calendar)["2026-11-24"] == nil)
        let archive = try AppDataBackup.create(defaults: loaded, backgroundURL: URL(fileURLWithPath: "/private/tmp/dayperk-calendar-missing-background.png"))
        #expect(try AppDataBackup.validate(archive)[LeaveRequests.storageKey] != nil)
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier == "app.dayperk.documentation.calendar-interaction"))
    func nativeLeaveAndMakeupControlsCanBeClickedAndSaved() async throws {
        let seed = LocalPreviewMode.Seed(cityID: "hangzhou", monthlySalary: 114_514, allowance: 0, annualBonusMonths: 2, trackedHours: 6)
        try LocalPreviewMode.prepare(seed)
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        try LocalPreviewMode.apply(seed, to: model)
        model.access.unlockSettings(); LocalizationManager.shared.setLanguage(.chinese)
        var config = model.configuration; config.dateOverrides = [:]; config.overtimeDates = [:]
        config.rhythm.enabled = false; config.weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        try model.saveConfiguration(config)
        let host = NSHostingView(rootView: DayPerkPreferencesView(model: model, initialPage: .work))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1160, height: 860), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "薪咖 · 调休交互验证"; window.isReleasedWhenClosed = false; window.contentView = host
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close(); model.tracking.shutdown() }
        var sawLeave = false, sawMakeup = false, sawRemoval = false
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            if model.activeLeave(for: "2026-11-23")?.isCompensatory == true { sawLeave = true }
            if sawLeave && model.configuration.dateOverrides["2026-11-23"] == true && model.leaveDays["2026-11-23"] == nil {
                #expect(model.leaveRequests.isEmpty)
                sawMakeup = true
            }
            if sawMakeup && model.configuration.dateOverrides["2026-11-23"] == nil && model.leaveDays["2026-11-23"] == nil { sawRemoval = true }
            if sawRemoval {
                #expect(model.leaveRequests.allSatisfy { $0.excludedPortions?["2026-11-23"] == .full })
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("未完成：切换并保存调休休假、改为调休上班、恢复默认且旧休假不恢复")
    }
}
