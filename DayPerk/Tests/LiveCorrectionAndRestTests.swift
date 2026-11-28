import Foundation
@testable import DayPerk
import Testing

struct LiveCorrectionAndRestTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var plan: WorkPlan {
        WorkPlan(startMinute: 9 * 60, endMinute: 17 * 60, ratePerSecond: 1,
                 breakPeriods: [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)], dayStartMinute: 0, grossRatePerSecond: 1, referenceSeconds: 6 * 3600, automation: .enabledForTesting)
    }

    private func controller() -> WorkTrackingController {
        WorkTrackingController(defaults: UserDefaults(suiteName: "live-correction-\(UUID().uuidString)")!, calendar: calendar, observeSystem: false)
    }

    @Test func earlyClockOutSettlesWithoutDiscardingLastSecondsOrResumingAutomatically() throws {
        let start = date(23, 10)
        var p = plan
        p.expectedIncomes = ["2026-11-23": 1000]
        var state = WorkTrackingState()
        state.setWorking(true, at: start, plan: p, calendar: calendar)
        state.finishToday(at: start.addingTimeInterval(5), plan: p, calendar: calendar)
        #expect(!state.isWorking && state.pendingPause == nil)
        #expect(state.days[0].seconds == 5 && state.days[0].earned == 5)
        #expect(state.days[0].expectedIncome == 1000)
        #expect(state.days[0].settledAt == start.addingTimeInterval(5))
        state.setCaffeine(true, at: start.addingTimeInterval(6), plan: p, calendar: calendar)
        #expect(state.caffeineEnabled && !state.isWorking)
        state.finishToday(at: start.addingTimeInterval(20), plan: p, calendar: calendar)
        #expect(state.days[0].seconds == 5)
        let restored = try JSONDecoder().decode(WorkTrackingState.self, from: JSONEncoder().encode(state))
        #expect(restored.isSettled(at: start, plan: p, calendar: calendar))
        #expect(!restored.isSettled(at: date(24, 10), plan: p, calendar: calendar))
    }

    @Test func earlySettlementFreezesValuesUntilManualRefreshOrResume() {
        let start = date(23, 10)
        var p = plan
        p.expectedIncomes = ["2026-11-23": 1000]
        var state = WorkTrackingState()
        state.setWorking(true, at: start, plan: p, calendar: calendar)
        state.finishToday(at: start.addingTimeInterval(60), plan: p, calendar: calendar)
        p.ratePerSecond = 2; p.expectedIncomes = ["2026-11-23": 2000]
        state.reprice(using: p, at: start.addingTimeInterval(120), calendar: calendar)
        #expect(state.days[0].earned == 60 && state.days[0].expectedIncome == 1000)
        state.reprice(using: p, at: start.addingTimeInterval(120), calendar: calendar, refreshHistory: true)
        #expect(state.days[0].earned == 120 && state.days[0].expectedIncome == 2000)
        state.setWorking(true, at: start.addingTimeInterval(125), plan: p, calendar: calendar)
        state.accrue(until: start.addingTimeInterval(130), plan: p, calendar: calendar)
        #expect(state.days[0].seconds == 65 && state.days[0].earned == 130)
        #expect(state.days[0].settledAt == nil)
    }

    @Test func earlyClockOutBlocksUnlockAutomationButManualSwitchStillWorks() {
        let c = controller(), start = date(23, 9)
        c.updatePlan(plan, at: start)
        c.setWorking(true, at: start)
        c.finishToday(at: start.addingTimeInterval(60)) { $0.seconds + 100 }
        #expect(c.state.days[0].expectedIncome == 160)
        c.startAfterDataUnlock(at: start.addingTimeInterval(120))
        #expect(!c.state.isWorking)
        c.setWorking(true, at: start.addingTimeInterval(125))
        c.updatePlan(plan, at: start.addingTimeInterval(130))
        #expect(c.state.isWorking && c.state.days[0].seconds == 65)
    }

    @Test func correctingWhileRunningReplacesTimeAndContinuesFromSaveInstant() throws {
        let c = controller(), start = date(23, 10)
        c.updatePlan(plan, at: start)
        c.setWorking(true, at: start)
        try c.correctToday(seconds: 3600, at: start.addingTimeInterval(5))
        #expect(c.state.isWorking && c.state.days[0].seconds == 3600 && c.state.days[0].earned == 3600)
        #expect(c.state.days[0].manualAdjustment == nil)
        c.updatePlan(plan, at: start.addingTimeInterval(8))
        #expect(c.state.days[0].seconds == 3603 && c.state.days[0].earned == 3603)
        c.setWorking(false, at: start.addingTimeInterval(9))
        #expect(c.state.days[0].seconds == 3604)
        try c.correctToday(seconds: 7200, at: start.addingTimeInterval(10))
        c.setWorking(true, at: start.addingTimeInterval(11))
        #expect(c.state.days[0].seconds == 7200 && c.state.days[0].earned == 7200)
        #expect(throws: DayPerkInputError.self) { try c.correctToday(seconds: -1) }
    }

    @Test func unpaidTimeUsesConfiguredThresholdAndDoesNotIncreaseOvertimePay() {
        var p = plan
        p.overtimeDates = ["2026-11-23": 2]
        var day = WorkDayTotal(id: "2026-11-23", seconds: 7 * 3600, overtimeSeconds: 7 * 3600)
        p.stamp(&day, calendar: calendar)
        #expect(day.unpaidOvertimeSeconds == 3600)
        #expect(day.trackingSummary(registeredOvertime: true) == L10n.text("ui.overtime_tracked.3025c3ee") + " 07:00:00" + L10n.format("ui.1.41fcf945", "01:00:00"))
        #expect(day.trackingSummary(registeredOvertime: false) == L10n.text("ui.tracked.81c4bc02") + " 07:00:00" + L10n.format("ui.1.41fcf945", "01:00:00"))
        #expect(p.registeredOvertimeGross(for: day, rate: 1) == 6 * 3600 * 2)
        #expect(p.amount(for: day) == 7 * 3600)
        day.seconds = 6 * 3600
        #expect(day.trackingSummary(registeredOvertime: false) == L10n.text("ui.tracked.81c4bc02") + " 06:00:00")
        day.seconds += 1
        #expect(day.unpaidOvertimeSeconds == 1)
    }

    @Test func thresholdSnapshotsRemainFrozenUntilExplicitHistoricalRefresh() {
        var state = WorkTrackingState(days: [WorkDayTotal(id: "2026-11-22", seconds: 8 * 3600, earned: 100, referenceSeconds: 7 * 3600),
                                            WorkDayTotal(id: "2026-11-23", seconds: 8 * 3600)])
        state.reprice(using: plan, at: date(23, 12), calendar: calendar)
        #expect(state.days[0].unpaidOvertimeSeconds == 3600 && state.days[0].earned == 100)
        #expect(state.days[1].unpaidOvertimeSeconds == 2 * 3600)
        state.reprice(using: plan, at: date(23, 12), calendar: calendar, refreshHistory: true)
        #expect(state.days[0].unpaidOvertimeSeconds == 2 * 3600)
    }

    @Test func lockingAndUnlockingHaveSeparateStartAndEndWindows() {
        for time in [date(23, 11, 30), date(23, 12), date(23, 12, 2), date(23, 16, 30), date(23, 17, 30)] {
            #expect(plan.isNearRestStart(time, calendar: calendar))
        }
        for time in [date(23, 11, 29), date(23, 12, 31), date(23, 13, 45), date(23, 16, 29), date(23, 17, 31), date(28, 12)] {
            #expect(!plan.isNearRestStart(time, calendar: calendar))
        }
        for time in [date(23, 8, 30), date(23, 9, 30), date(23, 13, 30), date(23, 14, 30)] {
            #expect(plan.isNearRestEnd(time, calendar: calendar))
        }
        for time in [date(23, 8, 29), date(23, 9, 31), date(23, 11, 45), date(23, 13, 29), date(23, 14, 31), date(28, 13, 45)] {
            #expect(!plan.isNearRestEnd(time, calendar: calendar))
        }
        var p = plan
        p.overtimeDates = ["2026-11-28": 3]
        #expect(p.isNearRestStart(date(28, 12), calendar: calendar))
        #expect(p.isNearRestEnd(date(28, 13, 45), calendar: calendar))
        p.breakPeriods = []
        #expect(!p.isNearRestStart(date(23, 12), calendar: calendar))
        #expect(!p.isNearRestEnd(date(23, 13, 45), calendar: calendar))
        p.endMinute = 23 * 60 + 50; p.dayStartMinute = 240
        #expect(p.isNearRestStart(date(23, 23, 30), calendar: calendar))
        #expect(p.isNearRestStart(date(24, 0, 5), calendar: calendar))
        #expect(!p.isNearRestStart(date(24, 0, 21), calendar: calendar))
        p.startMinute = 20
        #expect(p.isNearRestEnd(date(23, 23, 55), calendar: calendar))
    }

    @MainActor @Test func onlySuccessfulUnlockInEndingWindowStartsTrackingWithoutCountingLockedTime() {
        let store = UserDefaults(suiteName: "rest-lock-\(UUID().uuidString)")!
        let c = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        var now = date(23, 11), granted = false
        let access = SalaryAccessController(defaults: store, now: { now }) { _, done in done(granted) }
        access.dataWillLock = { c.pauseForDataLock(at: now) }
        access.dataDidUnlock = { c.startAfterDataUnlock(at: now) }
        c.updatePlan(plan, at: now)
        c.setWorking(true, at: now)
        now = date(23, 11, 45)
        access.lockAllData()
        #expect(!c.state.isWorking && c.state.pendingPause == nil)
        #expect(c.state.days[0].seconds == 2700)
        now = date(23, 14)
        access.unlockAllData()
        #expect(access.isDataLocked && !c.state.isWorking)
        granted = true
        access.unlockAllData()
        #expect(!access.isDataLocked && c.state.isWorking)
        c.updatePlan(plan, at: now.addingTimeInterval(60))
        #expect(c.state.days[0].seconds == 2760)
        c.setWorking(false, at: now.addingTimeInterval(61))
        now = date(23, 16, 45)
        access.lockAllData(); access.unlockAllData()
        #expect(!c.state.isWorking)
    }

    @Test func lockNearBreakEndDoesNotStopWorkAndUnlockNearBreakStartDoesNotStartIt() {
        let c = controller(), start = date(23, 10)
        c.updatePlan(plan, at: start)
        c.setWorking(true, at: start)
        c.pauseForDataLock(at: date(23, 10, 30))
        #expect(c.state.isWorking)
        c.pauseForDataLock(at: date(23, 11, 45))
        c.startAfterDataUnlock(at: date(23, 12))
        #expect(!c.state.isWorking)
        c.startAfterDataUnlock(at: date(23, 13, 45))
        #expect(c.state.isWorking)
        c.pauseForDataLock(at: date(23, 13, 50))
        #expect(c.state.isWorking)
    }

    @Test func correctionClearsLegacyAmountAdjustmentButPreservesEndedDays() throws {
        let store = UserDefaults(suiteName: "legacy-correction-\(UUID().uuidString)")!
        let past = WorkDayTotal(id: "2026-11-22", seconds: 100, earned: 150, manualAdjustment: 50)
        let state = WorkTrackingState(days: [past, WorkDayTotal(id: "2026-11-23", seconds: 100, earned: 999, manualAdjustment: 899)])
        store.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        let c = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        var p = plan; p.overtimeDates["2026-11-23"] = 3
        c.updatePlan(p, at: date(23, 10))
        #expect(c.state.days[1].earned == 100 && c.state.days[1].manualAdjustment == nil)
        try c.correctToday(seconds: 7 * 3600, at: date(23, 10))
        let today = c.state.days[1]
        #expect(today.earned == 7 * 3600 && today.manualAdjustment == nil)
        #expect(today.overtimeSeconds == today.seconds && today.unpaidOvertimeSeconds == 3600)
        #expect(c.state.days[0].seconds == past.seconds && c.state.days[0].earned == past.earned && c.state.days[0].manualAdjustment == past.manualAdjustment)
    }

    @Test func unlockAfterRelaunchUsesEndingWindowAndDoesNotBackfill() {
        let store = UserDefaults(suiteName: "rest-relaunch-\(UUID().uuidString)")!
        let c = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        c.updatePlan(plan, at: date(23, 11))
        c.setWorking(true, at: date(23, 11))
        c.pauseForDataLock(at: date(23, 11, 45))
        let restarted = WorkTrackingController(defaults: store, calendar: calendar, observeSystem: false)
        restarted.updatePlan(plan, at: date(23, 13, 45))
        restarted.startAfterDataUnlock(at: date(23, 13, 45))
        restarted.updatePlan(plan, at: date(23, 13, 45).addingTimeInterval(1))
        #expect(restarted.state.isWorking && restarted.state.days[0].seconds == 2701)
    }

    @Test func automaticUnlockDoesNotApplyManualPauseDebounce() {
        let c = controller(), start = date(23, 13, 40)
        c.updatePlan(plan, at: start)
        c.setWorking(true, at: start)
        c.setWorking(false, at: start.addingTimeInterval(20))
        c.startAfterDataUnlock(at: start.addingTimeInterval(25))
        c.updatePlan(plan, at: start.addingTimeInterval(26))
        #expect(c.state.days[0].seconds == 21)
    }

    @MainActor @Test func eighteenOhTwoLockPausesButEndOfBreakLockDoesNot() {
        let c = controller()
        var p = plan
        p.endMinute = 22 * 60
        p.breakPeriods = [WorkBreak(startMinute: 18 * 60, endMinute: 19 * 60)]
        var now = date(24, 17)
        let access = SalaryAccessController(defaults: UserDefaults(suiteName: "evening-lock-\(UUID().uuidString)")!, now: { now }) { _, done in done(true) }
        access.dataWillLock = { c.pauseForDataLock(at: now) }
        access.dataDidUnlock = { c.startAfterDataUnlock(at: now) }
        c.updatePlan(p, at: now); c.setWorking(true, at: now)
        now = date(24, 18, 2)
        access.lockAllData()
        #expect(access.isDataLocked && !c.state.isWorking)
        access.unlockAllData()
        #expect(!c.state.isWorking)
        now = date(24, 18, 45)
        access.lockAllData(); access.unlockAllData()
        #expect(c.state.isWorking)
        access.lockAllData()
        #expect(c.state.isWorking)
        now = date(24, 22, 2)
        access.lockAllData()
        #expect(!c.state.isWorking)
        #expect(p.isNearRestEnd(date(24, 19, 2), calendar: calendar))
        #expect(!p.isNearRestStart(date(24, 18, 30), calendar: calendar))
        p.breakPeriods = [WorkBreak(startMinute: 18 * 60, endMinute: 18 * 60 + 20)]
        #expect(!p.isNearRestStart(date(24, 18, 2), calendar: calendar))
    }

    @MainActor @Test func doubleLockBeforeEveningBreakStopsTrackingAndFailedUnlockKeepsItPaused() {
        let c = controller()
        defer { c.discardForRestore() }
        var p = plan
        p.endMinute = 22 * 60
        p.breakPeriods = [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60), WorkBreak(startMinute: 18 * 60, endMinute: 19 * 60)]
        p.automation = WorkAutomationRules()
        p.automation.lockPausesWork = true
        var now = date(26, 17, 40)
        let access = SalaryAccessController(defaults: UserDefaults(suiteName: "before-evening-lock-\(UUID().uuidString)")!, now: { now }) { _, done in done(false) }
        access.dataWillLock = { c.pauseForDataLock(at: now) }
        access.dataDidUnlock = { c.startAfterDataUnlock(at: now) }
        c.updatePlan(p, at: now); c.setWorking(true, at: now)
        now = date(26, 17, 58)
        var opened = false
        let clicks = StatusItemClickHandler()
        clicks.handle(clickCount: 1, single: { opened = true }, double: { access.lockAllData() })
        clicks.handle(clickCount: 2, single: { opened = true }, double: { access.lockAllData() })
        #expect(access.isDataLocked && !c.state.isWorking && !opened)
        #expect(abs((c.state.days.first?.seconds ?? 0) - 18 * 60) < 0.001)
        access.unlockAllData()
        #expect(!access.settingsUnlocked && !c.state.isWorking)
        c.checkpoint(at: now.addingTimeInterval(60))
        #expect(abs((c.state.days.first?.seconds ?? 0) - 18 * 60) < 0.001)
    }

    @MainActor @Test func dataLockDoesNotBlockManualTrackingOrCaffeineSwitches() {
        let c = controller()
        defer { c.shutdown() }
        var p = plan; p.linkCaffeine = false
        c.updatePlan(p)
        let access = SalaryAccessController(defaults: UserDefaults(suiteName: "locked-controls-\(UUID().uuidString)")!) { _, done in done(false) }
        access.lockAllData()
        c.setWorking(true)
        #expect(c.state.isWorking && access.isDataLocked)
        c.setWorking(false)
        #expect(!c.state.isWorking && access.isDataLocked)
        c.setCaffeine(true)
        #expect(c.state.caffeineEnabled && c.errorMessage == nil && access.isDataLocked)
        c.setCaffeine(false)
        #expect(!c.state.caffeineEnabled && access.isDataLocked && !access.settingsUnlocked)
    }
}
