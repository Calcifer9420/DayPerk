import Foundation
import Testing
@testable import DayPerk

struct BrewDatePickerTests {
    @Test func calendarShowsRealDaysAcrossLeapYearsAndDaylightSaving() throws {
        for zone in ["Asia/Shanghai", "America/Los_Angeles", "Europe/Berlin"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone)); calendar.firstWeekday = 2
            for (year, month, count) in [(2026, 2, 28), (2028, 2, 29), (2026, 3, 31), (2026, 11, 30)] {
                let date = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 20)))
                let cells = BrewDatePicker.days(in: date, calendar: calendar)
                let days = cells.compactMap { $0 }
                #expect(days.count == count)
                #expect(Set(days).count == count)
                #expect(days.map { calendar.component(.day, from: $0) } == Array(1 ... count))
                #expect(days.allSatisfy { calendar.component(.month, from: $0) == month })
                #expect(cells.prefix { $0 == nil }.count == (calendar.component(.weekday, from: days[0]) + 5) % 7)
            }
        }
    }

    @Test func leaveDateBoundsIncludeBothEndsAndRejectOtherDays() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func date(_ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        let range = try date(10, 28) ... date(11, 4)
        #expect(try BrewDatePicker.contains(date(10, 28, 0), in: range, calendar: calendar))
        #expect(try BrewDatePicker.contains(date(11, 4, 23), in: range, calendar: calendar))
        #expect(try !BrewDatePicker.contains(date(10, 27), in: range, calendar: calendar))
        #expect(try !BrewDatePicker.contains(date(11, 5), in: range, calendar: calendar))
    }
}
