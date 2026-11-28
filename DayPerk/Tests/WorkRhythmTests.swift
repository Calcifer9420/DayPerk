import Foundation
@testable import DayPerk
import Testing

struct WorkRhythmTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    @Test func oneOnOneOffRepeatsAcrossWeekendsAndDST() throws {
        let rhythm = WorkRhythm(enabled: true, anchorDay: "2026-03-06", cycleDays: [true, false])
        try rhythm.validate()
        #expect(rhythm.isWorkday(date(2026, 3, 6), calendar: calendar))
        #expect(!rhythm.isWorkday(date(2026, 3, 7), calendar: calendar))
        #expect(rhythm.isWorkday(date(2026, 3, 8), calendar: calendar))
        #expect(!rhythm.isWorkday(date(2026, 3, 9), calendar: calendar))
        #expect(!rhythm.isWorkday(date(2026, 3, 5), calendar: calendar))
    }
    @Test func alternatingSaturdaysRepeatAcrossDSTAndYearBoundary() throws {
        let rhythm = WorkRhythm(enabled: true, anchorDay: "2026-03-02")
        try rhythm.validate()
        #expect(!rhythm.isWorkday(date(2026, 3, 7), calendar: calendar))
        #expect(rhythm.isWorkday(date(2026, 3, 14), calendar: calendar))
        #expect(!rhythm.isWorkday(date(2026, 3, 21), calendar: calendar))
        #expect(rhythm.isWorkday(date(2026, 2, 28), calendar: calendar))
        var plan = WorkPlan(rhythm: rhythm)
        #expect(plan.regularWorkdays(year: 2026, month: 3, calendar: calendar) == 24)
        plan.dateOverrides["2026-03-14"] = false
        #expect(!plan.isScheduledWorkday(date(2026, 3, 14), calendar: calendar))
        plan.overtimeDates["2026-03-14"] = 2.55
        #expect(plan.isWorkday(date(2026, 3, 14), calendar: calendar))
        #expect(plan.regularWorkdays(year: 2026, month: 3, calendar: calendar) == 23)
    }
    @Test func rateLimitsAcceptOnlyHundredthsUpTo99() {
        for value in [0.01, 1, 1.5, 2.55, 99] { #expect(OvertimeRateInput.isValid(value)) }
        for value in [0, -1, 1.001, 99.01, .infinity, .nan] { #expect(!OvertimeRateInput.isValid(value)) }
    }
    @Test func manualRefreshNeverConvertsCompletedCurrencySnapshots() {
        var state = WorkTrackingState()
        state.days = [WorkDayTotal(id: "2026-03-01", seconds: 3600, earned: 100, expectedIncome: 200, currencyCode: "CNY"),
                      WorkDayTotal(id: "2026-03-02", seconds: 3600, earned: 100, expectedIncome: 200, currencyCode: "USD")]
        let plan = WorkPlan(ratePerSecond: 1, currencyCode: "USD")
        state.reprice(using: plan, at: date(2026, 3, 10), calendar: calendar, refreshHistory: true)
        #expect(state.days[0].earned == 100 && state.days[0].currencyCode == "CNY")
        #expect(state.days[1].earned == 3600 && state.days[1].currencyCode == "USD")
    }

    @Test func productionIdentifierCannotSeedHistory() throws {
        let suite = "DayPerk-mock-isolation-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sentinel = Data([0, 1, 2]); defaults.set(sentinel, forKey: "manualWorkTrackingV1")
        let seed = LocalPreviewMode.Seed(cityID: "beijing", monthlySalary: 114514, allowance: 0, annualBonusMonths: 2, trackedHours: 6,
            history: [.init(dayOffset: -1, hours: 10, overtimeMultiplier: nil), .init(dayOffset: -2, hours: 6, overtimeMultiplier: 2.5)])
        #expect(throws: DayPerkInputError.self) { try LocalPreviewMode.prepare(seed, defaults: defaults, bundleID: "app.dayperk.mac") }
        #expect(defaults.data(forKey: "manualWorkTrackingV1") == sentinel)
        try LocalPreviewMode.prepare(seed, defaults: defaults, bundleID: "app.dayperk.documentation.test")
        let state = try JSONDecoder().decode(WorkTrackingState.self, from: #require(defaults.data(forKey: "manualWorkTrackingV1")))
        #expect(state.days.count == 2 && state.days[0].seconds == 36000 && state.days[1].overtimeSeconds == 21600)
        #expect(!LocalPreviewMode.enabled)
    }
}
