import Foundation
@testable import DayPerk
import Testing

struct ChinaHolidayCalendarTests {
    @Test func bundledCalendarsContainBothPublishedYearsWithOfficialSources() throws {
        let plans = ChinaHolidayCalendar.bundledPlans()
        #expect(plans.map(\.year) == [2026, 2027])
        for plan in plans {
            #expect(try plan.validated(for: plan.year).days.count > 30)
        }
    }

    private var plan: ChinaHolidayPlan {
        ChinaHolidayPlan(year: 2027, papers: ["https://www.gov.cn/zhengce/202611/example.htm"], days: [
            ChinaHolidayDay(name: "元旦", date: "2027-01-01", isOffDay: true),
            ChinaHolidayDay(name: "春节", date: "2027-01-31", isOffDay: false),
        ])
    }

    @Test func validatesYearOfficialSourcesAndRealDates() throws {
        #expect(try plan.validated(for: 2027) == plan)
        #expect(throws: ChinaHolidayError.self) { try plan.validated(for: 2026) }
        var changed = plan
        changed.papers = ["https://gov.cn.example.org/policy"]
        #expect(throws: ChinaHolidayError.self) { try changed.validated(for: 2027) }
        changed = plan; changed.days[0].date = "2027-02-30"
        #expect(throws: ChinaHolidayError.self) { try changed.validated(for: 2027) }
        changed = plan; changed.days = []
        #expect(throws: ChinaHolidayError.self) { try changed.validated(for: 2027) }
    }

    @Test func januaryPlansMayIncludePreviousDecemberButNotOtherYears() throws {
        var changed = plan
        changed.days.append(ChinaHolidayDay(name: "元旦", date: "2026-12-31", isOffDay: false))
        #expect(try changed.validated(for: 2027).days.count == 3)
        changed.days[2].date = "2026-11-30"
        #expect(throws: ChinaHolidayError.self) { try changed.validated(for: 2027) }
    }

    @Test func importingPreservesCustomOverridesAndOtherYears() {
        let current = ["2027-01-01": true, "2026-10-01": false, "2028-01-01": true]
        let merged = ChinaHolidayCalendar.merging([plan], into: current, imported: [:])
        #expect(merged.overrides["2027-01-01"] == true)
        #expect(merged.overrides["2027-01-31"] == true)
        #expect(merged.overrides["2026-10-01"] == false)
        #expect(merged.overrides["2028-01-01"] == true)
        #expect(merged.imported["2027-01-01"] == nil)
        #expect(merged.imported["2027-01-31"] == true)
    }

    @Test func refreshUpdatesOnlyUneditedImportedDaysAndRemovesObsoleteDates() {
        let imported = ["2027-01-01": false, "2027-01-02": false, "2027-01-31": false]
        let current = ["2027-01-01": true, "2027-01-02": false, "2027-01-31": false]
        let merged = ChinaHolidayCalendar.merging([plan], into: current, imported: imported)
        #expect(merged.overrides["2027-01-01"] == true)
        #expect(merged.overrides["2027-01-02"] == nil)
        #expect(merged.overrides["2027-01-31"] == true)
    }

    @MainActor @Test func cachedOfficialPlansAreAvailableWithoutNetwork() throws {
        let name = "ChinaHolidayCalendarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = ChinaHolidayCache(plans: [2027: plan], imported: ["2027-01-01": false], updatedAt: Date())
        try defaults.set(JSONEncoder().encode(cache), forKey: "chinaHolidayCalendarV1")
        let service = ChinaHolidayCalendar(defaults: defaults)
        let holiday = try #require(ChinaHolidayCalendar.date("2027-01-01"))
        #expect(service.day(holiday)?.isOffDay == true)
        #expect(service.cache.imported["2027-01-01"] == false)
    }
}
