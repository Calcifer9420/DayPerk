import Foundation

struct DayWorkSchedule: Codable, Equatable {
    var startMinute = 540
    var endMinute = 1080
    var breakMode: WorkBreakMode = .totalHours
    var breakMinutes = 60
    var breaks: [WorkBreak] = []

    var spanMinutes: Int { (endMinute - startMinute + 1440) % 1440 }
    func offset(_ minute: Int) -> Int { (minute - startMinute + 1440) % 1440 }
    var breakRanges: [Range<Int>] {
        breaks.map { offset($0.startMinute) ..< (offset($0.startMinute) + ($0.endMinute - $0.startMinute + 1440) % 1440) }
    }
    var restMinutes: Int { breakMode == .totalHours ? breakMinutes : breakRanges.reduce(0) { $0 + $1.count } }
    var referenceMinutes: Int { spanMinutes - restMinutes }
    var timeSummary: String { String(format: "%02d:%02d–%02d:%02d", startMinute / 60, startMinute % 60, endMinute / 60, endMinute % 60) }

    func morningReferenceMinutes(boundary: Int) -> Int {
        let split = min(spanMinutes, offset(boundary))
        let rest: Int
        if breakMode == .timeRanges {
            rest = breakRanges.reduce(0) { $0 + max(0, min(split, $1.upperBound) - $1.lowerBound) }
        } else {
            // 只有总休息时长时优先从后半段扣除；具体休息时段按实际交集计算。
            rest = max(0, restMinutes - (spanMinutes - split))
        }
        return max(0, min(referenceMinutes, split - rest))
    }

    func validate() throws {
        guard (0 ..< 1440).contains(startMinute), (0 ..< 1440).contains(endMinute), spanMinutes > 0,
              breaks.allSatisfy({ (0 ..< 1440).contains($0.startMinute) && (0 ..< 1440).contains($0.endMinute) }),
              breakMinutes >= 0, referenceMinutes > 0 else { throw DayPerkInputError(message: L10n.text("ui.choose_a_valid_shift_and_leave_at_l.658bc88d")) }
        if breakMode == .timeRanges {
            let ranges = breakRanges.sorted { $0.lowerBound < $1.lowerBound }
            for (i, range) in ranges.enumerated() {
                guard !range.isEmpty, range.upperBound <= spanMinutes,
                      i == 0 || ranges[i - 1].upperBound <= range.lowerBound else {
                    throw DayPerkInputError(message: L10n.text("ui.breaks_must_be_inside_the_shift_and.5a4aac53"))
                }
            }
        }
    }
}

/// 按工作地的民用日期匹配；数组中靠前的规则优先，不改变当天是否需要上班。
struct WorkScheduleRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var enabled = true
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var intervalWeeks = 1
    var anchorDay = "2026-01-05"
    var effectiveFromDay: String?
    var schedule = DayWorkSchedule()

    func matches(_ day: String) -> Bool {
        guard effectiveFromDay.map({ day >= $0 }) ?? true else { return false }
        return matchesRecurrence(day)
    }

    /// 手动修正历史时只核对星期和周次，允许主动套用创建前的规则。
    func matchesRecurrence(_ day: String) -> Bool {
        guard enabled, intervalWeeks > 0,
              let date = ChinaHolidayCalendar.date(day), let anchor = ChinaHolidayCalendar.date(anchorDay) else { return false }
        var calendar = ChinaHolidayCalendar.calendar
        calendar.firstWeekday = 2
        guard weekdays.contains(calendar.component(.weekday, from: date)),
              let first = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
              let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let days = calendar.dateComponents([.day], from: first, to: current).day else { return false }
        return (days / 7) % intervalWeeks == 0
    }

    func validate() throws {
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1 ... 7).contains($0) }),
              (1 ... 52).contains(intervalWeeks), ChinaHolidayCalendar.date(anchorDay) != nil,
              effectiveFromDay.map({ ChinaHolidayCalendar.date($0) != nil }) ?? true else {
            throw DayPerkInputError(message: L10n.text("schedule.rule_invalid"))
        }
        try schedule.validate()
    }
}

/// 以锚点所在周的星期一为第一周，负数周差也保持稳定循环。
struct WorkRhythm: Codable, Equatable {
    var enabled = false
    var anchorDay = "2026-01-05"
    var weeks: [Set<Int>] = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6, 7]]
    var cycleDays: [Bool]?
    var daySchedules: [String: DayWorkSchedule]?
    var observesPublicHolidays: Bool?
    // 可选字段让旧配置和旧备份继续使用统一时间；两种循环的键分开保留。
    var cycleSchedules: [String: DayWorkSchedule]?
    var scheduleRules: [WorkScheduleRule]?

    static func daySlot(_ index: Int) -> String { "day:\(index)" }
    static func weekSlot(_ index: Int, weekday: Int) -> String { "week:\(index):\(weekday)" }

    /// 旧规则保留原记录；新规则只从创建当天起自动匹配，编辑和排序不重置生效日。
    mutating func startNewRules(comparedTo previous: WorkRhythm, on day: String) {
        guard var rules = scheduleRules else { return }
        for index in rules.indices {
            if let existing = previous.scheduleRules?.first(where: { $0.id == rules[index].id }) {
                rules[index].effectiveFromDay = existing.effectiveFromDay
            } else if rules[index].effectiveFromDay == nil {
                rules[index].effectiveFromDay = day
            }
        }
        scheduleRules = rules
    }

    /// 只调整顺序，按稳定标识保留规则内容和当前编辑对象。
    @discardableResult mutating func moveScheduleRule(_ id: UUID, to targetID: UUID) -> Bool {
        guard var rules = scheduleRules,
              let source = rules.firstIndex(where: { $0.id == id }),
              let target = rules.firstIndex(where: { $0.id == targetID }), source != target else { return false }
        rules.insert(rules.remove(at: source), at: target)
        scheduleRules = rules
        return true
    }

    private func anchor(in calendar: Calendar) -> Date? {
        guard ChinaHolidayCalendar.date(anchorDay) != nil else { return nil }
        let parts = anchorDay.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func dayIndex(_ date: Date, calendar: Calendar, count: Int) -> Int? {
        guard count > 0, let anchor = anchor(in: calendar),
              let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: date)).day else { return nil }
        return (distance % count + count) % count
    }

    private func weekIndex(_ date: Date, calendar source: Calendar) -> Int? {
        var calendar = source; calendar.firstWeekday = 2
        guard !weeks.isEmpty, let anchor = anchor(in: calendar),
              let first = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
              let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let days = calendar.dateComponents([.day], from: first, to: current).day else { return nil }
        return ((days / 7) % weeks.count + weeks.count) % weeks.count
    }

    func customSchedule(for day: String) -> DayWorkSchedule? {
        if let exact = daySchedules?[day] { return exact }
        if let rule = scheduleRules?.first(where: { $0.matches(day) }) { return rule.schedule }
        guard enabled, let date = ChinaHolidayCalendar.date(day) else { return nil }
        let calendar = ChinaHolidayCalendar.calendar
        if let cycleDays, let index = dayIndex(date, calendar: calendar, count: cycleDays.count) {
            return cycleSchedules?[Self.daySlot(index)]
        }
        guard let index = weekIndex(date, calendar: calendar) else { return nil }
        return cycleSchedules?[Self.weekSlot(index, weekday: calendar.component(.weekday, from: date))]
    }

    func schedule(for day: String, fallback: DayWorkSchedule) -> DayWorkSchedule {
        customSchedule(for: day) ?? fallback
    }

    func isWorkday(_ date: Date, calendar source: Calendar) -> Bool {
        if let cycleDays, let index = dayIndex(date, calendar: source, count: cycleDays.count) {
            return cycleDays[index]
        }
        guard let index = weekIndex(date, calendar: source) else { return false }
        return weeks[index].contains(source.component(.weekday, from: date))
    }

    func validate() throws {
        guard ChinaHolidayCalendar.date(anchorDay) != nil, (1 ... 8).contains(weeks.count),
              weeks.allSatisfy({ $0.allSatisfy { (1 ... 7).contains($0) } }) else {
            throw DayPerkInputError(message: L10n.text("ui.choose_one_to_eight_cycle_weeks_a_v.c734287c"))
        }
        if let cycleDays {
            guard (1 ... 56).contains(cycleDays.count) else {
                throw DayPerkInputError(message: L10n.text("ui.choose_one_to_56_cycle_days_and_at.4283c7b1"))
            }
        }
        for (day, schedule) in daySchedules ?? [:] {
            guard ChinaHolidayCalendar.date(day) != nil else { throw DayPerkInputError(message: L10n.text("ui.choose_a_valid_shift_date.68b267c8")) }
            try schedule.validate()
        }
        for (slot, schedule) in cycleSchedules ?? [:] {
            let parts = slot.split(separator: ":")
            let validDay = parts.count == 2 && parts[0] == "day" && Int(parts[1]).map { (0 ..< 56).contains($0) } == true
            let validWeek = parts.count == 3 && parts[0] == "week" && Int(parts[1]).map { (0 ..< 8).contains($0) } == true && Int(parts[2]).map { (1 ... 7).contains($0) } == true
            guard validDay || validWeek else { throw DayPerkInputError(message: L10n.text("schedule.cycle_invalid")) }
            try schedule.validate()
        }
        let rules = scheduleRules ?? []
        guard Set(rules.map(\.id)).count == rules.count else { throw DayPerkInputError(message: L10n.text("schedule.rule_invalid")) }
        for rule in rules { try rule.validate() }
    }
}

enum OvertimeRateInput {
    static func isValid(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value <= 99 && abs(value * 100 - (value * 100).rounded()) < 0.000001
    }
}
