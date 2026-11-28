import Foundation

enum WorkDataCorrection {
    static func dates(from: Date, through: Date, asOf: Date, plan: WorkPlan, calendar: Calendar,
                      rule: WorkScheduleRule? = nil) throws -> [String] {
        let start = calendar.startOfDay(for: from), end = calendar.startOfDay(for: through)
        guard start <= end, end <= calendar.startOfDay(for: asOf),
              let distance = calendar.dateComponents([.day], from: start, to: end).day,
              (0 ... 36_600).contains(distance) else {
            throw DayPerkInputError(message: L10n.text("correction.invalid_dates"))
        }
        if let rule { try rule.validate() }
        return (0 ... distance).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = WorkPlan.dayKey(date, calendar: calendar)
            guard plan.isScheduledWorkday(date, calendar: calendar) || plan.overtimeDates[key] != nil,
                  rule?.matchesRecurrence(key) ?? true else { return nil }
            return key
        }
    }
}
