import Foundation
@testable import DayPerk
import Testing

struct StorageCompatibilityTests {
    @Test func profileAndScheduleKeepExistingKeysAndIdentifiers() throws {
        let profile = SalaryProfile(name: "Example", monthlySalary: 100, workdaysPerMonth: 20)
        let data = try JSONEncoder().encode(profile)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(keys.keys) == ["id", "name", "monthlySalary", "workdaysPerMonth", "currency", "createdAt", "updatedAt"])
        let loaded = try JSONDecoder().decode(SalaryProfile.self, from: data)
        #expect(loaded.id == profile.id && loaded.monthlySalary == profile.monthlySalary)
        let schedule = ReferenceSchedule(startTime: Date.createTime(hour: 9, minute: 0), endTime: Date.createTime(hour: 18, minute: 0))
        let restored = try JSONDecoder().decode(ReferenceSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(restored.id == schedule.id && restored.workdays == schedule.workdays)
        #expect(Weekday.allCases.first == .monday && Weekday.sunday.calendarWeekday == 1)
    }

    @Test func selectedDisplayPrecisionStillAppliesToAmounts() {
        let settings = MoneyDisplaySettings.shared
        let previous = settings.displayDecimalPlaces
        defer { settings.setDisplayPrecision(previous) }
        settings.setDisplayPrecision(0)
        #expect(!settings.formatAmount(1234.56).contains("."))
        #expect(settings.formatAmount(-0.4) == settings.formatAmount(0))
        settings.setDisplayPrecision(2)
        #expect(settings.formatAmount(1234.56).contains(".56"))
        #expect(settings.formatAmount(-0.0017017543864312756) == settings.formatAmount(0))
    }
}
