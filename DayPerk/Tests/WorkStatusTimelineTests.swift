import Foundation
import Testing
@testable import DayPerk

struct WorkStatusTimelineTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private var plan: WorkPlan { WorkPlan(startMinute: 540, endMinute: 1080, ratePerSecond: 1) }
    private func period(_ day: Int) -> DateInterval { .init(start: at(day, 4), end: at(day + 1, 4)) }

    @Test func aTimelineCannotRepresentAWeekOrMonth() {
        #expect(WorkStatusTimeline.make(segments: [], days: [], plan: plan, interval: .init(start: at(23, 4), end: at(30, 4)), calendar: calendar, now: at(27, 12)) == nil)
    }

    @Test func endpointsIncludeEarlyClockInLateClockOutAndKeepTheWholePresetShift() throws {
        let early = WorkDayTotal(id: "2026-11-27", settledAt: at(28, 1, 30), clockedInAt: at(27, 8, 30))
        let value = try #require(WorkStatusTimeline.make(segments: [], days: [early], plan: plan, interval: period(27), calendar: calendar, now: at(28, 12)))
        #expect(value.interval.start == at(27, 8, 30) && value.interval.end == at(28, 1, 30))
        let late = WorkDayTotal(id: "2026-11-27", settledAt: at(27, 16), clockedInAt: at(27, 10))
        let other = try #require(WorkStatusTimeline.make(segments: [], days: [late], plan: plan, interval: period(27), calendar: calendar, now: at(28, 12)))
        #expect(other.interval.start == at(27, 9) && other.interval.end == at(27, 18))
    }

    @Test func overnightPresetAndContiguousActivityKeepNextDayTimestamps() throws {
        var night = plan; night.startMinute = 1320; night.endMinute = 360
        let segments = [WorkStatusSegment(statusID: "focus", start: at(27, 21, 30), end: at(28, 5)),
                        WorkStatusSegment(statusID: "rest", start: at(28, 5), end: at(28, 6, 30)),
                        WorkStatusSegment(statusID: "focus", start: at(28, 6, 30), end: at(28, 7)),
                        WorkStatusSegment(statusID: "busy", start: at(28, 9), end: at(28, 10))]
        let value = try #require(WorkStatusTimeline.make(segments: segments, days: [], plan: night, interval: period(27), calendar: calendar, now: at(28, 12)))
        #expect(value.interval.start == at(27, 21, 30) && value.interval.end == at(28, 7))
        #expect(value.segments == Array(segments.prefix(3)))
    }

    @Test func hoverFindsTheActualPieceWithoutFillingGapsAndAnglesSelectTheSameStatus() throws {
        let pieces = [WorkStatusSegment(statusID: "focus", start: at(27, 9), end: at(27, 10)),
                      WorkStatusSegment(statusID: "rest", start: at(27, 12), end: at(27, 13)),
                      WorkStatusSegment(statusID: "focus", start: at(27, 14), end: at(27, 15))]
        let value = try #require(WorkStatusTimeline.make(segments: pieces, days: [], plan: plan, interval: period(27), calendar: calendar, now: at(27, 18)))
        #expect(value.segment(at: 0)?.id == pieces[0].id)
        #expect(value.segment(at: 2.0 / 9) == nil)
        #expect(value.segment(at: 3.0 / 9)?.statusID == "rest")
        #expect(value.segment(at: 5.0 / 9)?.id == pieces[2].id)
        #expect(value.segment(at: 1) == nil && value.segment(at: .nan) == nil)
        let totals = WorkStatusReport.totals(pieces, definitions: WorkStatusDefinition.presets, interval: value.interval)
        #expect(WorkStatusTimeline.status(at: 0.2, totals: totals) == "focus")
        #expect(WorkStatusTimeline.status(at: 0.9, totals: totals) == "rest")
        #expect(WorkStatusTimeline.status(at: 1, totals: totals) == nil)
    }

    @Test func clockInSurvivesPausesAndEncodingWhileShortMistakesRollBack() throws {
        var p = plan; p.automation.discardShortSessions = false; p.automation.bridgeShortPauses = false
        var state = WorkTrackingState()
        state.setWorking(true, at: at(27, 8, 30), plan: p, calendar: calendar)
        state.setWorking(false, at: at(27, 12), plan: p, calendar: calendar)
        state.setWorking(true, at: at(27, 14), plan: p, calendar: calendar)
        state.finishToday(at: at(28, 1), plan: p, calendar: calendar)
        let day = try #require(state.days.first { $0.id == "2026-11-27" })
        #expect(day.clockedInAt == at(27, 8, 30) && day.settledAt == at(28, 1))
        #expect(day.scheduledStart == at(27, 9) && day.scheduledEnd == at(27, 18))
        #expect(try JSONDecoder().decode(WorkTrackingState.self, from: JSONEncoder().encode(state)) == state)
        let legacy = try JSONDecoder().decode(WorkDayTotal.self, from: Data("{\"id\":\"2026-11-27\",\"seconds\":0,\"overtimeSeconds\":0,\"earned\":0}".utf8))
        #expect(legacy.clockedInAt == nil && legacy.scheduledStart == nil && legacy.scheduledEnd == nil)
        var mistake = WorkTrackingState()
        mistake.setWorking(true, at: at(27, 9), plan: plan, calendar: calendar)
        mistake.setWorking(false, at: at(27, 9).addingTimeInterval(2), plan: plan, calendar: calendar)
        #expect(mistake.days.isEmpty)
    }
}
