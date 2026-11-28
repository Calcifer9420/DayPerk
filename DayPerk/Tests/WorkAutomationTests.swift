import Foundation
@testable import DayPerk
import Testing

struct WorkAutomationTests {
    @Test func protectionWindowIsConfigurableValidatedAndLegacyCompatible() throws {
        #expect(WorkAutomationRules().protectionInterval == 10)
        #expect(try JSONDecoder().decode(WorkAutomationRules.self, from: JSONEncoder().encode(WorkAutomationRules())).protectionInterval == 10)
        for seconds in [1, 3, 20, 300] {
            var rules = WorkAutomationRules(); rules.tapProtectionSeconds = seconds
            try rules.validate()
            #expect(rules.protectionInterval == Double(seconds))
        }
        for seconds in [0, -1, 301] {
            var rules = WorkAutomationRules(); rules.tapProtectionSeconds = seconds
            #expect(throws: DayPerkInputError.self) { try rules.validate() }
        }
    }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
    }
    private var plan: WorkPlan {
        WorkPlan(startMinute: 9 * 60, endMinute: 18 * 60, ratePerSecond: 1,
                 breakPeriods: [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)], linkCaffeine: true, automation: .enabledForTesting)
    }

    @Test func caffeineStartStopAndBufferCanBeDisabledIndependently() {
        var p = plan
        p.automation.caffeineStartsWork = false
        var s = WorkTrackingState()
        s.setCaffeine(true, at: date(10), plan: p, calendar: calendar)
        #expect(s.caffeineEnabled && !s.isWorking)
        p.automation.caffeineStartsWork = true; p.automation.caffeineBuffer = false
        #expect(!p.isWithinWorkHours(date(8, 45), calendar: calendar))
        #expect(p.isWithinWorkHours(date(9), calendar: calendar))
        p.automation.caffeineBuffer = true
        #expect(p.isWithinWorkHours(date(8, 45), calendar: calendar))
        #expect(!p.isWithinWorkHours(date(12, 30), calendar: calendar))
        s.setWorking(true, at: date(10), plan: p, calendar: calendar)
        p.automation.caffeineStopsWork = false
        s.setCaffeine(false, at: date(20), plan: p, calendar: calendar)
        #expect(!s.caffeineEnabled && s.isWorking)
        p.linkCaffeine = false
        s.setCaffeine(true, at: date(20), plan: p, calendar: calendar)
        s.setCaffeine(false, at: date(21), plan: p, calendar: calendar)
        #expect(s.isWorking)
        p.linkCaffeine = true; p.automation.caffeineStopsWork = true
        s.setCaffeine(true, at: date(21), plan: p, calendar: calendar)
        s.setCaffeine(false, at: date(21, 1), plan: p, calendar: calendar)
        #expect(!s.isWorking)
    }

    @Test func dataLockAndUnlockRespectTheirOwnSwitches() {
        let c = WorkTrackingController(defaults: UserDefaults(suiteName: "automation-lock-\(UUID().uuidString)")!, calendar: calendar, observeSystem: false)
        var p = plan; p.automation.lockPausesWork = false
        c.updatePlan(p, at: date(11)); c.setWorking(true, at: date(11))
        c.pauseForDataLock(at: date(12, 2))
        #expect(c.state.isWorking)
        p.automation.lockPausesWork = true; p.automation.unlockStartsWork = false
        c.updatePlan(p, at: date(12, 2)); c.pauseForDataLock(at: date(12, 2))
        c.startAfterDataUnlock(at: date(13, 45))
        #expect(!c.state.isWorking)
        p.automation.unlockStartsWork = true
        c.updatePlan(p, at: date(13, 45)); c.startAfterDataUnlock(at: date(13, 45))
        #expect(c.state.isWorking)
    }

    @Test func debounceRulesAreOptionalAndDoNotAlterOtherDays() {
        var p = plan
        p.automation.discardShortSessions = false
        p.automation.bridgeShortPauses = false
        var s = WorkTrackingState()
        s.setWorking(true, at: date(10), plan: p, calendar: calendar)
        s.setWorking(false, at: date(10).addingTimeInterval(5), plan: p, calendar: calendar)
        #expect(s.days[0].seconds == 5)
        s.setWorking(true, at: date(10).addingTimeInterval(8), plan: p, calendar: calendar)
        #expect(s.days[0].seconds == 5)
        s.accrue(until: date(10).addingTimeInterval(13), plan: p, calendar: calendar)
        #expect(s.days[0].seconds == 10)
        s.recoverAfterRelaunch(discardShortSessions: false)
        #expect(s.days[0].seconds == 10)
    }

    @Test func systemEventsControlCaffeineAndTrackingSeparately() {
        for pause in [false, true] {
            for caffeineOff in [false, true] {
                var p = plan
                p.automation.pauseOnSystemLock = pause
                p.automation.caffeineOffOnSystemLock = caffeineOff
                var s = WorkTrackingState(caffeineEnabled: true)
                s.setWorking(true, at: date(10), plan: p, calendar: calendar)
                s.suspend(at: date(10, 1), plan: p, calendar: calendar)
                #expect(s.isWorking == !pause)
                #expect(s.caffeineEnabled == !caffeineOff)
            }
        }
    }

    @Test func allRulesRoundTripAndHelpKeepsFormulasIntact() throws {
        var rules = WorkAutomationRules()
        rules.caffeineStartsWork = false; rules.lockPausesWork = false; rules.pauseOnSystemLock = false
        #expect(try JSONDecoder().decode(WorkAutomationRules.self, from: JSONEncoder().encode(rules)) == rules)
        #expect(RuleHelpText.bulleted("只在工作日生效。排除午休。") == "• 只在工作日生效\n\n• 排除午休")
        #expect(RuleHelpText.bulleted("Workdays only. Exclude breaks.").contains("\n\n• Exclude breaks."))
        let formula = "月基数 ÷ 21 天 ÷ 8 小时。按保存配置计算。"
        #expect(RuleHelpText.bulleted(formula) == formula)
        #expect(!LocalPreviewMode.enabled)
        #expect(!LocalPreviewMode.permitsSampleData(bundleIdentifier: "app.dayperk.mac"))
        #expect(!LocalPreviewMode.permitsSampleData(bundleIdentifier: "app.dayperk.mac"))
        #expect(LocalPreviewMode.permitsSampleData(bundleIdentifier: "app.dayperk.local-preview"))
        #expect(LocalPreviewMode.permitsSampleData(bundleIdentifier: "app.dayperk.documentation.review"))
    }
}

// 行为测试显式选择全开场景，避免默认值改变时掩盖联动回归。
extension WorkAutomationRules {
    static var enabledForTesting: Self {
        Self(caffeineStartsWork: true, caffeineStopsWork: true, caffeineBuffer: true, lockPausesWork: true, unlockStartsWork: true,
             discardShortSessions: true, bridgeShortPauses: true, pauseOnSystemLock: true, caffeineOffOnSystemLock: true)
    }
}
