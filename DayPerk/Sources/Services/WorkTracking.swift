import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

struct WorkDayTotal: Codable, Identifiable, Equatable {
    var id: String
    var seconds: Double = 0
    var overtimeSeconds: Double = 0
    var earned: Double = 0
    var manualAdjustment: Double?
    var ratePerSecond: Double?
    var expectedIncome: Double?
    var overtimeMultiplier: Double?
    var grossRatePerSecond: Double?
    var referenceSeconds: Double?
    var currencyCode: String?
    var registeredDailyGross: Double?
    var settledAt: Date?
    var clockedInAt: Date?
    var scheduledStart: Date?
    var scheduledEnd: Date?

    var unpaidOvertimeSeconds: Double {
        guard let referenceSeconds, referenceSeconds.isFinite, referenceSeconds >= 0 else { return 0 }
        return max(0, seconds - referenceSeconds)
    }

    func trackingSummary(registeredOvertime: Bool) -> String {
        let title = registeredOvertime ? L10n.text("ui.overtime_tracked.3025c3ee") : L10n.text("ui.tracked.81c4bc02")
        let base = "\(title) \(WorkDurationInput.format(seconds))"
        return unpaidOvertimeSeconds > 0 ? base + L10n.format("ui.1.41fcf945", String(describing: WorkDurationInput.format(unpaidOvertimeSeconds))) : base
    }
}

enum WorkBreakMode: String, Codable, CaseIterable {
    case totalHours = "总休息时长"
    case timeRanges = "指定休息时段"
}

struct WorkBreak: Codable, Identifiable, Equatable {
    var id: UUID = .init()
    var startMinute: Int
    var endMinute: Int
}

struct WorkAutomationRules: Codable, Equatable {
    var caffeineStartsWork = false
    var caffeineStopsWork = false
    var caffeineBuffer = false
    var lockPausesWork = false
    var unlockStartsWork = false
    var discardShortSessions = true
    var bridgeShortPauses = true
    var pauseOnSystemLock = false
    var caffeineOffOnSystemLock = false
    var tapProtectionSeconds: Int?
    var protectionInterval: TimeInterval { TimeInterval(min(300, max(1, tapProtectionSeconds ?? 10))) }
    func validate() throws {
        if let seconds = tapProtectionSeconds, !(1 ... 300).contains(seconds) {
            throw DayPerkInputError(message: L10n.text("automation.invalid_seconds"))
        }
    }
}

enum DayArrangement: String, CaseIterable, Identifiable {
    case automatic = "ui.follow_weekday.da8940f4"
    case makeup = "ui.make_up_workday.07f65c10"
    case rest = "ui.day_off.384ea035"
    case overtime = "ui.overtime_day.7623c214"
    var id: Self { self }
    var title: String { L10n.text(rawValue) }
}

struct WorkPlan {
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var dateOverrides: [String: Bool] = [:]
    var startMinute: Int = 510
    var endMinute: Int = 1050
    var ratePerSecond: Double = 0
    var overtimeMultiplier: Double = 2
    var breakPeriods: [WorkBreak] = []
    var linkCaffeine = false
    var overtimeDates: [String: Double] = [:]
    var dayRates: [String: Double] = [:]
    var dayStartMinute: Int = 240
    var expectedIncomes: [String: Double] = [:]
    var grossRatePerSecond: Double = 0
    var dayGrossRates: [String: Double] = [:]
    var defaultDailyExpectedIncome: Double = 0
    var referenceSeconds: Double = 8 * 3600
    var rhythm = WorkRhythm()
    var currencyCode = "CNY"
    var automation = WorkAutomationRules()
    var registeredDailyGross: Double?
    var leaveDays: [String: LeaveDay] = [:]

    func schedule(for key: String) -> DayWorkSchedule {
        rhythm.schedule(for: key, fallback: DayWorkSchedule(startMinute: startMinute, endMinute: endMinute,
            breakMode: breakPeriods.isEmpty ? .totalHours : .timeRanges,
            breakMinutes: max(0, (endMinute - startMinute + 1440) % 1440 - Int(referenceSeconds / 60)), breaks: breakPeriods))
    }

    func scheduledReferenceSeconds(for key: String) -> Double {
        if let schedule = rhythm.customSchedule(for: key) { return Double(schedule.referenceMinutes * 60) }
        return referenceSeconds
    }

    func timeValueRate(dailyIncome: Double, for key: String) -> Double {
        // 时间规则改变每天的分母，不改变日工资；请假单独影响收入和剩余应工作时长。
        let seconds = scheduledReferenceSeconds(for: key)
        return seconds > 0 ? dailyIncome / seconds : 0
    }

    func referenceSeconds(for key: String) -> Double {
        guard let leave = leaveDays[key] else { return scheduledReferenceSeconds(for: key) }
        let schedule = schedule(for: key)
        let morning = Double(schedule.morningReferenceMinutes(boundary: leave.boundaryMinute ?? 720) * 60)
        let afternoon = max(0, scheduledReferenceSeconds(for: key) - morning)
        return (leave.morning == nil ? morning : 0) + (leave.afternoon == nil ? afternoon : 0)
    }

    func expectedWorkSeconds(for day: WorkDayTotal, calendar: Calendar, preservingExisting: Bool = true) -> Double {
        let parts = day.id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return 0 }
        let hasBudget = isScheduledWorkday(date, calendar: calendar) || overtimeDates[day.id] != nil
        let planned = hasBudget ? max(0, referenceSeconds(for: day.id)) : 0
        // 旧快照优先；未登记上班的休息日没有应工作时长。
        if preservingExisting, let frozen = day.referenceSeconds, frozen.isFinite, frozen >= 0,
           hasBudget || (day.expectedIncome ?? 0) > 0 || day.overtimeSeconds > 0 || (day.overtimeMultiplier ?? 0) > 0 { return frozen }
        return planned
    }

    func isOnLeave(_ date: Date, calendar: Calendar) -> Bool {
        let key = businessDayKey(date, calendar: calendar)
        guard let leave = leaveDays[key] else { return false }
        let schedule = schedule(for: key)
        var minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if minute < dayStartMinute { minute += 1440 }
        let offset = min(schedule.spanMinutes, max(0, minute - shiftBounds(for: date, calendar: calendar).start))
        let firstHalf = offset < min(schedule.spanMinutes, schedule.offset(leave.boundaryMinute ?? 720))
        return firstHalf ? leave.morning != nil : leave.afternoon != nil
    }

    func shiftBounds(for date: Date, calendar: Calendar) -> (start: Int, end: Int, breaks: [Range<Int>]) {
        let schedule = schedule(for: businessDayKey(date, calendar: calendar))
        let start = schedule.startMinute < dayStartMinute ? schedule.startMinute + 1440 : schedule.startMinute
        return (start, start + schedule.spanMinutes, schedule.breakMode == .timeRanges ? schedule.breakRanges.map { ($0.lowerBound + start) ..< ($0.upperBound + start) } : [])
    }

    func scheduledInterval(for key: String, calendar: Calendar) -> DateInterval? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let shift = schedule(for: key)
        let start = shift.startMinute < dayStartMinute ? shift.startMinute + 1440 : shift.startMinute
        func point(_ minute: Int) -> Date? {
            guard let date = calendar.date(byAdding: .day, value: minute / 1440, to: day) else { return nil }
            return calendar.date(bySettingHour: minute % 1440 / 60, minute: minute % 60, second: 0, of: date)
        }
        guard let first = point(start), let last = point(start + shift.spanMinutes), last > first else { return nil }
        return DateInterval(start: first, end: last)
    }

    func amount(for day: WorkDayTotal) -> Double {
        // 时间价值始终按基础时薪计；登记加班的报酬由工资预测独立计算。
        max(0, day.seconds * (dayRates[day.id] ?? ratePerSecond) + (day.manualAdjustment ?? 0))
    }

    func registeredOvertimeGross(for day: WorkDayTotal, rate: Double) -> Double {
        if let multiplier = day.overtimeMultiplier {
            if let daily = day.registeredDailyGross { return day.overtimeSeconds > 0 ? daily * multiplier : 0 }
            return min(day.overtimeSeconds, day.referenceSeconds ?? day.overtimeSeconds) * multiplier * (day.grossRatePerSecond ?? rate)
        }
        guard let multiplier = overtimeDates[day.id] else { return 0 }
        if let daily = registeredDailyGross { return day.seconds > 0 ? daily * multiplier : 0 }
        return min(day.seconds, referenceSeconds(for: day.id)) * multiplier * (day.grossRatePerSecond ?? rate)
    }

    func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        if overtimeDates[businessDayKey(date, calendar: calendar)] != nil {
            return true
        }
        return isRegularWorkday(date, calendar: calendar)
    }

    func regularWorkdays(year: Int, month: Int, calendar: Calendar) -> Int {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return 0 }
        return range.filter { day in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return false }
            return isScheduledWorkday(date, calendar: calendar)
        }.count
    }

    func monthlyReferenceSeconds(year: Int, month: Int, calendar: Calendar) -> Double {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return 0 }
        return range.reduce(0) { total, day in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                  isScheduledWorkday(date, calendar: calendar) else { return total }
            return total + max(0, scheduledReferenceSeconds(for: Self.dayKey(date, calendar: calendar)))
        }
    }

    /// 日历和发薪日使用民用日期，不受凌晨业务日边界或个人加班登记影响。
    func isScheduledWorkday(_ date: Date, calendar: Calendar) -> Bool {
        dateOverrides[Self.dayKey(date, calendar: calendar)] ?? (rhythm.enabled ? rhythm.isWorkday(date, calendar: calendar) : weekdays.contains(calendar.component(.weekday, from: date)))
    }

    func canMakeupWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let key = Self.dayKey(date, calendar: calendar)
        return leaveDays[key]?.isEmpty == false || (overtimeDates[key] == nil && !isScheduledWorkday(date, calendar: calendar))
    }

    func isRegularWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let start = businessDayStart(for: date, calendar: calendar)
        return isScheduledWorkday(start, calendar: calendar)
    }

    func isWithinWorkHours(_ date: Date, calendar: Calendar) -> Bool {
        var minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if minute < dayStartMinute { minute += 1440 }
        let bounds = shiftBounds(for: date, calendar: calendar)
        let buffer = automation.caffeineBuffer ? 30 : 0
        return isWorkday(date, calendar: calendar) && minute >= bounds.start - buffer && minute <= bounds.end + buffer
            && !bounds.breaks.contains { $0.contains(minute) } && !isOnLeave(date, calendar: calendar)
    }

    func canClockOut(_ date: Date, calendar: Calendar) -> Bool {
        isWorkday(date, calendar: calendar) && referenceSeconds(for: businessDayKey(date, calendar: calendar)) > 0
    }

    func hasReachedShiftEnd(_ date: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: businessDayStart(for: date, calendar: calendar))
        let offset = shiftBounds(for: date, calendar: calendar).end
        guard let day = calendar.date(byAdding: .day, value: offset / 1440, to: start),
              let end = calendar.date(bySettingHour: offset / 60 % 24, minute: offset % 60, second: 0, of: day) else { return false }
        return date >= end
    }

    func isNearRestStart(_ date: Date, calendar: Calendar) -> Bool {
        // 短休息的开始与结束窗口可能重叠；临近结束时优先保留计费。
        let bounds = shiftBounds(for: date, calendar: calendar)
        let starts = bounds.breaks.filter { !isNearBoundary(date, minutes: [$0.upperBound], calendar: calendar) }.map(\.lowerBound)
        return isNearBoundary(date, minutes: [bounds.end] + starts, calendar: calendar)
    }

    func isNearRestEnd(_ date: Date, calendar: Calendar) -> Bool {
        let bounds = shiftBounds(for: date, calendar: calendar)
        return isNearBoundary(date, minutes: [bounds.start] + bounds.breaks.map(\.upperBound), calendar: calendar)
    }

    private func isNearBoundary(_ date: Date, minutes: [Int], calendar: Calendar) -> Bool {
        guard isWorkday(date, calendar: calendar) else { return false }
        func businessMinute(_ value: Int) -> Double { Double(value < dayStartMinute ? value + 1440 : value) }
        let minute = businessMinute(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
            + Double(calendar.component(.second, from: date)) / 60
        return minutes.contains { boundary in
            let end = businessMinute(boundary)
            return abs(minute - end) <= 30
        }
    }

    func businessDayStart(for date: Date, calendar: Calendar) -> Date {
        let minute = min(1439, max(0, dayStartMinute))
        let midnight = calendar.startOfDay(for: date)
        let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight) ?? midnight
        if date >= start {
            return start
        }
        let previous = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: previous) ?? previous
    }

    func businessDayKey(_ date: Date, calendar: Calendar) -> String {
        Self.dayKey(businessDayStart(for: date, calendar: calendar), calendar: calendar)
    }

    func expectedIncome(for key: String, calendar: Calendar) -> Double {
        if let value = expectedIncomes[key] {
            return value
        }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return 0 }
        return isScheduledWorkday(day, calendar: calendar) && referenceSeconds > 0 ? defaultDailyExpectedIncome * (leaveDays[key]?.payableFraction ?? 1) : 0
    }

    func stamp(_ day: inout WorkDayTotal, calendar: Calendar, preservingExisting: Bool = false) {
        // 旧日期缺少参考工时快照时不猜测，只有主动重算该日期时才补齐。
        if !preservingExisting {
            day.referenceSeconds = referenceSeconds(for: day.id); day.currencyCode = currencyCode
            day.registeredDailyGross = registeredDailyGross
            let shift = scheduledInterval(for: day.id, calendar: calendar)
            day.scheduledStart = shift?.start; day.scheduledEnd = shift?.end
        }
        if !preservingExisting || day.ratePerSecond == nil {
            day.ratePerSecond = preservingExisting && day.seconds > 0
                ? max(0, (day.earned - (day.manualAdjustment ?? 0)) / day.seconds)
                : (dayRates[day.id] ?? ratePerSecond)
        }
        if !preservingExisting || day.expectedIncome == nil {
            day.expectedIncome = expectedIncome(for: day.id, calendar: calendar)
        }
        if !preservingExisting || day.overtimeMultiplier == nil {
            day.overtimeMultiplier = overtimeDates[day.id] ?? (preservingExisting && day.overtimeSeconds > 0 ? overtimeMultiplier : 0)
        }
        if !preservingExisting || day.grossRatePerSecond == nil {
            day.grossRatePerSecond = dayGrossRates[day.id] ?? grossRatePerSecond
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

struct PaydayRule: Codable, Equatable {
    var usesLastDay = true
    var day = 10
    var advanceOnRestDay = false

    func date(year: Int, month: Int, plan: WorkPlan, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let days = calendar.range(of: .day, in: .month, for: first),
              var result = calendar.date(from: DateComponents(year: year, month: month, day: usesLastDay ? days.count : min(days.count, max(1, day)), hour: 12)) else { return nil }
        guard advanceOnRestDay else { return result }
        // 限制查找范围，避免整个日历没有工作日时无限回退。
        for _ in 0 ..< 370 {
            if plan.isScheduledWorkday(result, calendar: calendar) {
                return result
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: result) else { return nil }
            result = previous
        }
        return nil
    }
}

/// 只有显式状态变更才联动；每秒刷新不会覆盖用户手动暂停的决定。
struct WorkPause: Codable, Equatable {
    var at: Date
    var days: [WorkDayTotal]
    var sessionStartedAt: Date?
    var sessionBaseline: [WorkDayTotal]?
}

struct WorkTrackingState: Codable, Equatable {
    var caffeineEnabled = false
    var isWorking = false
    var lastTick: Date?
    var days: [WorkDayTotal] = []
    var sessionStartedAt: Date?
    var sessionBaseline: [WorkDayTotal]?
    var pendingPause: WorkPause?
    var pendingClockOut: WorkPause?
    var securedSurplusDay: String?
    var activeWorkday: String?

    mutating func checkDepartureSurplus(at now: Date, plan: WorkPlan, calendar: Calendar) {
        let key = plan.businessDayKey(now, calendar: calendar)
        guard securedSurplusDay != key, plan.isWorkday(now, calendar: calendar) else { return }
        let start = plan.businessDayStart(for: now, calendar: calendar)
        let endOffset = plan.shiftBounds(for: now, calendar: calendar).end
        let endMinute = endOffset % 1440
        let endDay = calendar.date(byAdding: .day, value: endOffset / 1440, to: calendar.startOfDay(for: start))
        guard let endDay,
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay) else { return }
        let remaining = end.timeIntervalSince(now)
        let rate = plan.dayRates[key] ?? plan.ratePerSecond
        let expected = plan.expectedIncome(for: key, calendar: calendar)
        let earned = days.first { $0.id == key }?.earned ?? 0
        guard (0 ... 1800).contains(remaining), rate.isFinite, rate > 0,
              expected.isFinite, earned.isFinite else { return }
        // 按持续计时至下班作保守预测；触发结果独立于片段撤销，保留至业务日结束。
        if expected - earned - remaining * rate > 1800 * rate {
            securedSurplusDay = key
        }
    }

    func isSettled(at date: Date, plan: WorkPlan, calendar: Calendar) -> Bool {
        days.first { $0.id == plan.businessDayKey(date, calendar: calendar) }?.settledAt != nil
    }

    mutating func finishToday(at now: Date, plan: WorkPlan, calendar: Calendar) {
        accrue(until: now, plan: plan, calendar: calendar)
        let key = plan.businessDayKey(now, calendar: calendar)
        guard !isSettled(at: now, plan: plan, calendar: calendar) else { return }
        pendingClockOut = isWorking ? WorkPause(at: now, days: days, sessionStartedAt: sessionStartedAt, sessionBaseline: sessionBaseline) : nil
        if !days.contains(where: { $0.id == key }) { days.append(WorkDayTotal(id: key)) }
        if let i = days.firstIndex(where: { $0.id == key }), days[i].settledAt == nil {
            plan.stamp(&days[i], calendar: calendar)
            days[i].earned = plan.amount(for: days[i])
            days[i].settledAt = now
        }
        // 结算立即落盘；短时间撤回只恢复同一业务日的计费片段。
        isWorking = false; lastTick = nil
        activeWorkday = nil
        sessionStartedAt = nil; sessionBaseline = nil; pendingPause = nil
    }

    mutating func setWorking(_ enabled: Bool, at now: Date, plan: WorkPlan, calendar: Calendar) {
        guard enabled != isWorking else { return }
        accrue(until: now, plan: plan, calendar: calendar)
        if enabled {
            let key = plan.businessDayKey(now, calendar: calendar)
            activeWorkday = key
            if plan.automation.bridgeShortPauses, let pause = pendingClockOut,
               (0 ... plan.automation.protectionInterval).contains(now.timeIntervalSince(pause.at)), plan.businessDayKey(pause.at, calendar: calendar) == key {
                days = pause.days; sessionStartedAt = pause.sessionStartedAt; sessionBaseline = pause.sessionBaseline
                isWorking = true; lastTick = pause.at; pendingClockOut = nil; pendingPause = nil
                reprice(using: plan, at: now, calendar: calendar)
                accrue(until: now, plan: plan, calendar: calendar)
                return
            }
            pendingClockOut = nil
            if let i = days.firstIndex(where: { $0.id == key }), days[i].settledAt != nil {
                days[i].settledAt = nil
                reprice(using: plan, at: now, calendar: calendar)
            }
            if plan.automation.bridgeShortPauses, let pause = pendingPause, (0 ... plan.automation.protectionInterval).contains(now.timeIntervalSince(pause.at)) {
                days = pause.days
                sessionStartedAt = pause.sessionStartedAt
                sessionBaseline = pause.sessionBaseline
                isWorking = true
                lastTick = pause.at
                accrue(until: now, plan: plan, calendar: calendar)
            } else {
                sessionStartedAt = now
                sessionBaseline = days
            }
            pendingPause = nil
            if let index = days.firstIndex(where: { $0.id == key }) {
                if days[index].clockedInAt == nil { days[index].clockedInAt = now }
            } else {
                var day = WorkDayTotal(id: key, clockedInAt: now)
                plan.stamp(&day, calendar: calendar)
                days.append(day)
            }
        } else {
            pendingPause = WorkPause(at: now, days: days, sessionStartedAt: sessionStartedAt, sessionBaseline: sessionBaseline)
            if plan.automation.discardShortSessions, let start = sessionStartedAt, (0 ... plan.automation.protectionInterval).contains(now.timeIntervalSince(start)), let baseline = sessionBaseline {
                days = baseline
            }
            sessionStartedAt = nil
            sessionBaseline = nil
        }
        isWorking = enabled
        lastTick = enabled ? now : nil
    }

    mutating func setCaffeine(_ enabled: Bool, at now: Date, plan: WorkPlan, calendar: Calendar) {
        guard enabled != caffeineEnabled else { return }
        accrue(until: now, plan: plan, calendar: calendar)
        caffeineEnabled = enabled
        if plan.linkCaffeine, !(enabled && isSettled(at: now, plan: plan, calendar: calendar)), (enabled && plan.automation.caffeineStartsWork && plan.isWithinWorkHours(now, calendar: calendar)) || (!enabled && plan.automation.caffeineStopsWork && plan.isWorkday(now, calendar: calendar) && !plan.isWithinWorkHours(now, calendar: calendar)) {
            setWorking(enabled, at: now, plan: plan, calendar: calendar)
        }
    }

    mutating func suspend(at now: Date, plan: WorkPlan, calendar: Calendar) {
        // 系统事件分别遵守两个开关，不借咖啡因联动绕过计费暂停选项。
        if plan.automation.caffeineOffOnSystemLock { caffeineEnabled = false }
        if plan.automation.pauseOnSystemLock { setWorking(false, at: now, plan: plan, calendar: calendar) }
        pendingPause = nil; pendingClockOut = nil
    }

    mutating func accrue(until now: Date, plan: WorkPlan, calendar: Calendar) {
        guard isWorking, let previous = lastTick, now > previous else { return }
        var cursor = previous
        while cursor < now {
            let dayStart = plan.businessDayStart(for: cursor, calendar: calendar)
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayStart)) else { break }
            let minute = min(1439, max(0, plan.dayStartMinute))
            guard let nextDay = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: nextMidnight), nextDay > cursor else { break }
            let end = min(nextDay, now)
            let elapsed = end.timeIntervalSince(cursor)
            let key = plan.businessDayKey(cursor, calendar: calendar)
            let index: Int
            if let existing = days.firstIndex(where: { $0.id == key }) {
                index = existing
            } else {
                days.append(WorkDayTotal(id: key, referenceSeconds: plan.referenceSeconds(for: key))); index = days.count - 1
            }
            let isCurrentDay = key == plan.businessDayKey(now, calendar: calendar)
            plan.stamp(&days[index], calendar: calendar, preservingExisting: !isCurrentDay)
            days[index].seconds += elapsed
            if isCurrentDay {
                days[index].overtimeSeconds = plan.overtimeDates[key] == nil ? 0 : days[index].seconds
                days[index].earned = plan.amount(for: days[index])
            } else {
                if (days[index].overtimeMultiplier ?? 0) > 0 {
                    days[index].overtimeSeconds += elapsed
                }
                days[index].earned += elapsed * (days[index].ratePerSecond ?? 0)
            }
            cursor = end
        }
        lastTick = now
        activeWorkday = plan.businessDayKey(now, calendar: calendar)
    }

    mutating func reprice(using plan: WorkPlan, at now: Date, calendar: Calendar, refreshHistory: Bool = false, leaveChangedDays: Set<String> = [], updateCurrentDay: Bool = false, correctedDays: Set<String> = []) {
        let currentKey = plan.businessDayKey(now, calendar: calendar)
        func update(_ totals: inout [WorkDayTotal]) {
            for i in totals.indices {
                let sameCurrency = (totals[i].currencyCode ?? "CNY") == plan.currencyCode
                let shouldReprice = ((refreshHistory || correctedDays.contains(totals[i].id)) && sameCurrency)
                    || (totals[i].id == currentKey && (totals[i].settledAt == nil || updateCurrentDay))
                // 旧记录只补快照；既有金额和加班不因打开设置而改变。
                plan.stamp(&totals[i], calendar: calendar, preservingExisting: !shouldReprice)
                if leaveChangedDays.contains(totals[i].id), sameCurrency {
                    totals[i].referenceSeconds = plan.referenceSeconds(for: totals[i].id)
                    totals[i].expectedIncome = plan.expectedIncome(for: totals[i].id, calendar: calendar)
                }
                if shouldReprice {
                    if !correctedDays.contains(totals[i].id) { totals[i].manualAdjustment = nil }
                    totals[i].overtimeSeconds = plan.overtimeDates[totals[i].id] == nil ? 0 : totals[i].seconds
                    totals[i].earned = plan.amount(for: totals[i])
                }
            }
        }
        update(&days)
        if var pause = pendingPause {
            update(&pause.days)
            if var baseline = pause.sessionBaseline {
                update(&baseline); pause.sessionBaseline = baseline
            }
            pendingPause = pause
        }
        if var clockOut = pendingClockOut {
            update(&clockOut.days)
            if var baseline = clockOut.sessionBaseline { update(&baseline); clockOut.sessionBaseline = baseline }
            pendingClockOut = clockOut
        }
        if var baseline = sessionBaseline {
            update(&baseline)
            sessionBaseline = baseline
        }
        checkDepartureSurplus(at: now, plan: plan, calendar: calendar)
    }

    mutating func replaceCorrectedDay(_ day: WorkDayTotal) {
        func replace(_ values: inout [WorkDayTotal]) {
            if let i = values.firstIndex(where: { $0.id == day.id }) { values[i] = day }
            else { values.append(day); values.sort { $0.id < $1.id } }
        }
        replace(&days)
        if var baseline = sessionBaseline { replace(&baseline); sessionBaseline = baseline }
        if var pause = pendingPause {
            replace(&pause.days)
            if var baseline = pause.sessionBaseline { replace(&baseline); pause.sessionBaseline = baseline }
            pendingPause = pause
        }
        if var clockOut = pendingClockOut {
            replace(&clockOut.days)
            if var baseline = clockOut.sessionBaseline { replace(&baseline); clockOut.sessionBaseline = baseline }
            pendingClockOut = clockOut
        }
    }

    mutating func recoverAfterRelaunch(discardShortSessions: Bool = true, protectionInterval: TimeInterval = 10) {
        // 短误触撤销整个片段；其余只保留已落盘工时，不追计关闭期间。
        if discardShortSessions, let start = sessionStartedAt, let tick = lastTick,
           (0 ... protectionInterval).contains(tick.timeIntervalSince(start)), let baseline = sessionBaseline
        {
            days = baseline
        }
        sessionStartedAt = nil
        sessionBaseline = nil
        pendingPause = nil
        pendingClockOut = nil
        isWorking = false
        caffeineEnabled = false
        lastTick = nil
    }
}

final class WorkTrackingController: ObservableObject {
    @Published private(set) var state: WorkTrackingState
    @Published private(set) var errorMessage: String?
    var plan = WorkPlan()
    var shouldBridgePause: (() -> Bool)?
    private let defaults: any UserDataPreferences
    private(set) var calendar: Calendar
    private var timer: Timer?
    private var assertion: IOPMAssertionID?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastSavedAt = Date.distantPast
    private var importedCaffeine = false

    init(defaults: any UserDataPreferences = UserDataStore.shared, calendar: Calendar = .current, observeSystem: Bool = true, restoringBackup: Bool = false) {
        self.defaults = defaults
        self.calendar = calendar
        state = defaults.data(forKey: "manualWorkTrackingV1").flatMap {
            try? JSONDecoder().decode(WorkTrackingState.self, from: $0)
        } ?? WorkTrackingState()
        let rules = defaults.data(forKey: "dayperkAutomationRules").flatMap { try? JSONDecoder().decode(WorkAutomationRules.self, from: $0) } ?? WorkAutomationRules()
        if restoringBackup {
            importedCaffeine = state.caffeineEnabled
            state.caffeineEnabled = false
            state.lastTick = state.isWorking ? Date() : nil
            state.sessionStartedAt = nil; state.sessionBaseline = nil; state.pendingPause = nil; state.pendingClockOut = nil
        } else { state.recoverAfterRelaunch(discardShortSessions: rules.discardShortSessions, protectionInterval: rules.protectionInterval) }
        persist()
        guard observeSystem else { return }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend() }
            observers.append((workspace, observer))
        }
        let distributed = DistributedNotificationCenter.default()
        let lock = distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.suspend() }
        observers.append((distributed, lock))
    }

    deinit {
        timer?.invalidate()
        observers.forEach { $0.0.removeObserver($0.1) }
        if let assertion {
            IOPMAssertionRelease(assertion)
        }
    }

    func checkpoint(at now: Date = Date()) { state.accrue(until: now, plan: plan, calendar: calendar); persist() }

    func resumeImportedControls() {
        let working = state.isWorking
        if importedCaffeine { setCaffeine(true) }
        state.isWorking = working; state.lastTick = working ? Date() : nil
        state.sessionStartedAt = nil; state.sessionBaseline = nil; state.pendingPause = nil
        persist()
    }

    /// 导入完成后丢弃旧实例，不能让退出清理把旧账本写回新数据。
    func discardForRestore() { timer?.invalidate(); timer = nil; releaseAssertion() }

    func updateCalendar(_ value: Calendar, at now: Date = Date()) {
        guard value != calendar else { return }
        state.accrue(until: now, plan: plan, calendar: calendar)
        state.pendingPause = nil; state.pendingClockOut = nil
        state.sessionStartedAt = nil; state.sessionBaseline = nil
        calendar = value
        persist()
    }

    func updatePlan(_ newPlan: WorkPlan, at now: Date = Date(), leaveChangedDays: Set<String> = [], updateCurrentDay: Bool = false) {
        state.accrue(until: now, plan: plan, calendar: calendar)
        plan = newPlan
        state.reprice(using: plan, at: now, calendar: calendar, leaveChangedDays: leaveChangedDays, updateCurrentDay: updateCurrentDay)
        persist()
    }

    func refreshHistory(at now: Date = Date()) {
        state.accrue(until: now, plan: plan, calendar: calendar)
        state.reprice(using: plan, at: now, calendar: calendar, refreshHistory: true)
        persist()
    }

    func correctToday(seconds: Double, at now: Date = Date()) throws {
        guard seconds.isFinite, (0 ... 86400).contains(seconds) else {
            throw DayPerkInputError(message: L10n.text("ui.enter_a_valid_duration_of_no_more_t.6e00b440"))
        }
        state.accrue(until: now, plan: plan, calendar: calendar)
        let key = plan.businessDayKey(now, calendar: calendar)
        state.pendingPause = nil; state.pendingClockOut = nil
        let previous = state.days.first { $0.id == key }
        var day = WorkDayTotal(id: key, seconds: seconds, overtimeSeconds: plan.overtimeDates[key] == nil ? 0 : seconds, settledAt: previous?.settledAt, clockedInAt: previous?.clockedInAt)
        day.earned = plan.amount(for: day)
        plan.stamp(&day, calendar: calendar)
        if let i = state.days.firstIndex(where: { $0.id == key }) {
            state.days[i] = day
        } else {
            state.days.append(day)
        }
        // 修正值是新的权威基线，不能被旧片段撤销或暂停防抖覆盖。
        state.sessionStartedAt = nil
        state.sessionBaseline = nil
        state.lastTick = state.isWorking ? now : nil
        state.checkDepartureSurplus(at: now, plan: plan, calendar: calendar)
        persist()
    }

    func previewCorrection(_ key: String, seconds: Double, using pricingPlan: WorkPlan? = nil, at now: Date = Date()) -> WorkDayTotal {
        let old = state.days.first { $0.id == key }
        var day = old ?? WorkDayTotal(id: key)
        (pricingPlan ?? plan).stamp(&day, calendar: calendar,
            preservingExisting: old != nil && key != plan.businessDayKey(now, calendar: calendar))
        day.seconds = seconds; day.manualAdjustment = nil
        day.overtimeSeconds = (day.overtimeMultiplier ?? 0) > 0 ? seconds : 0
        day.earned = seconds * (day.ratePerSecond ?? 0)
        return day
    }

    func correctDay(_ key: String, seconds: Double, using pricingPlan: WorkPlan? = nil, at now: Date = Date()) throws {
        let currentKey = plan.businessDayKey(now, calendar: calendar)
        guard key <= currentKey, ChinaHolidayCalendar.date(key) != nil,
              seconds.isFinite, (0 ... 86400).contains(seconds) else {
            throw DayPerkInputError(message: L10n.text("correction.invalid_record"))
        }
        if key == currentKey { try correctToday(seconds: seconds, at: now); return }
        let old = state.days.first { $0.id == key }
        guard old == nil || (old?.currencyCode ?? "CNY") == plan.currencyCode else {
            throw DayPerkInputError(message: L10n.text("correction.currency_mismatch"))
        }
        var next = state
        next.accrue(until: now, plan: plan, calendar: calendar)
        let day = previewCorrection(key, seconds: seconds, using: pricingPlan, at: now)
        next.replaceCorrectedDay(day)
        try defaults.persist(["manualWorkTrackingV1": JSONEncoder().encode(next)])
        state = next
    }

    func correctSchedules(_ newPlan: WorkPlan, days: Set<String>, preferences: [String: Any], at now: Date = Date()) throws {
        var next = state
        next.accrue(until: now, plan: plan, calendar: calendar)
        next.reprice(using: newPlan, at: now, calendar: calendar, correctedDays: days)
        var changes = preferences
        changes["manualWorkTrackingV1"] = try JSONEncoder().encode(next)
        try defaults.persist(changes)
        plan = newPlan; state = next
    }

    func pauseForDataLock(at now: Date = Date()) {
        guard plan.automation.lockPausesWork, plan.isNearRestStart(now, calendar: calendar) else { return }
        state.accrue(until: now, plan: plan, calendar: calendar)
        state.isWorking = false
        state.lastTick = nil
        state.sessionStartedAt = nil
        state.sessionBaseline = nil
        // 已暂停时也撤销防误触补计，避免重新开工把隐藏或锁定期间的时间补回来。
        state.pendingPause = nil; state.pendingClockOut = nil
        persist()
    }

    func startAfterDataUnlock(at now: Date = Date()) {
        guard plan.automation.unlockStartsWork, !plan.isOnLeave(now, calendar: calendar), !state.isWorking, !state.isSettled(at: now, plan: plan, calendar: calendar), plan.isNearRestEnd(now, calendar: calendar) else { return }
        state.pendingPause = nil
        setWorking(true, at: now)
    }

    func finishToday(at now: Date = Date(), expectedIncome: ((WorkDayTotal) -> Double)? = nil) {
        errorMessage = nil
        state.finishToday(at: now, plan: plan, calendar: calendar)
        let key = plan.businessDayKey(now, calendar: calendar)
        if let expectedIncome, let i = state.days.firstIndex(where: { $0.id == key }) {
            state.days[i].expectedIncome = expectedIncome(state.days[i])
        }
        persist()
    }

    func setWorking(_ enabled: Bool, at now: Date = Date()) {
        errorMessage = nil
        guard !enabled || plan.ratePerSecond > 0 else {
            errorMessage = L10n.text("ui.save_valid_pay_and_working_time_set.817c0d5d")
            persist()
            return
        }
        if enabled, shouldBridgePause?() == false { state.pendingPause = nil }
        state.setWorking(enabled, at: now, plan: plan, calendar: calendar)
        state.checkDepartureSurplus(at: now, plan: plan, calendar: calendar)
        persist()
    }

    func setWorkingForStatus(_ enabled: Bool, at now: Date = Date()) {
        // 选状态是明确操作，不撤销短片段，也不把休息补记成工作。
        state.sessionStartedAt = nil; state.sessionBaseline = nil
        state.pendingPause = nil; state.pendingClockOut = nil
        setWorking(enabled, at: now)
        state.sessionStartedAt = nil; state.sessionBaseline = nil
        state.pendingPause = nil; state.pendingClockOut = nil
        persist()
    }

    func setCaffeine(_ enabled: Bool) {
        errorMessage = nil
        guard enabled != state.caffeineEnabled else { return }
        if enabled {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), L10n.text("ui.dayperk_work_keep_awake.00b5f32a") as CFString, &id)
            guard result == kIOReturnSuccess else {
                errorMessage = L10n.format("ui.1.4f0a0b86", String(describing: result))
                return
            }
            assertion = id
        } else {
            releaseAssertion()
        }
        state.setCaffeine(enabled, at: Date(), plan: plan, calendar: calendar)
        if state.isWorking, plan.ratePerSecond <= 0 {
            setWorking(false)
        }
        persist()
    }

    func suspend() {
        let now = Date()
        let cutoff = state.lastTick.flatMap { now.timeIntervalSince($0) > 5 ? $0 : nil } ?? now
        state.suspend(at: cutoff, plan: plan, calendar: calendar)
        if !state.caffeineEnabled { releaseAssertion() }
        persist()
    }

    func shutdown() {
        // 退出必须释放断言并停止工作，不能由系统锁屏偏好阻止清理。
        state.setWorking(false, at: Date(), plan: plan, calendar: calendar)
        state.caffeineEnabled = false
        state.pendingPause = nil; state.pendingClockOut = nil
        releaseAssertion(); persist(); timer?.invalidate()
    }

    private func tick() {
        // 正常刷新间隔超过 5 秒说明调度有中断；保守暂停，不追计可能的睡眠时间。
        if state.isWorking, let last = state.lastTick, Date().timeIntervalSince(last) > 5 {
            releaseAssertion()
            state.recoverAfterRelaunch(discardShortSessions: plan.automation.discardShortSessions, protectionInterval: plan.automation.protectionInterval)
            persist()
            errorMessage = L10n.text("ui.tracking_was_interrupted_and_paused.41bffb16")
            return
        }
        let now = Date()
        state.accrue(until: now, plan: plan, calendar: calendar)
        let previousSurplusDay = state.securedSurplusDay
        state.checkDepartureSurplus(at: now, plan: plan, calendar: calendar)
        if state.securedSurplusDay != previousSurplusDay || now.timeIntervalSince(lastSavedAt) >= 10 {
            persist()
        }
    }

    private func releaseAssertion() {
        if let assertion {
            IOPMAssertionRelease(assertion); self.assertion = nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: "manualWorkTrackingV1")
        }
        lastSavedAt = Date()
    }
}

/// 修正入口使用明确的时分秒，不把日期输入组件当作时长。
enum WorkDurationInput {
    static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds + 0.000001, Double(Int.max / 2)))
    }

    static func formatSeconds(_ seconds: Int, signed: Bool = false) -> String {
        let sign = signed && seconds != 0 ? (seconds > 0 ? "+" : "-") : ""
        let value = seconds.magnitude
        return sign + String(format: "%02llu:%02llu:%02llu", UInt64(value / 3600), UInt64(value / 60 % 60), UInt64(value % 60))
    }

    static func format(_ seconds: Double) -> String {
        formatSeconds(wholeSeconds(seconds.rounded()))
    }

    static func parse(_ text: String) throws -> Double {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
              (0 ... 24).contains(h), (0 ... 59).contains(m), (0 ... 59).contains(s), h * 3600 + m * 60 + s <= 86400
        else {
            throw DayPerkInputError(message: L10n.text("ui.enter_hours_minutes_seconds_for_exa.62260422"))
        }
        return Double(h * 3600 + m * 60 + s)
    }
}
