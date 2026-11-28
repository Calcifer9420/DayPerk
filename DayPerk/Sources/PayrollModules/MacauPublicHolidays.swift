import Foundation

/// 自行计算法定公众假期，不复制政府入口网站的日历编排或仅适用于公务员的豁免、补假。
enum MacauPublicHolidays {
    static func days(year: Int) throws -> [RegionalHoliday] {
        // 与内置薪酬、节假日资料的有效年度一致；新年度需核查清明和冬至日期后扩展。
        guard [2026, 2027].contains(year) else { throw DayPerkInputError(message: L10n.text("holiday.year_unavailable")) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Macau")!
        var chinese = Calendar(identifier: .chinese); chinese.timeZone = calendar.timeZone
        var result: [RegionalHoliday] = []
        func add(_ date: Date, _ name: String) {
            result.append(RegionalHoliday(date: WorkPlan.dayKey(date, calendar: calendar), name: name, localName: name, countryCode: "MO", types: ["Public"]))
        }
        for (month, day, name) in [(1, 1, "New Year's Day"), (5, 1, "Labour Day"), (10, 1, "National Day"),
            (10, 2, "holiday.mo.national_next"), (11, 2, "All Souls' Day"), (12, 8, "holiday.immaculate_conception"),
            (12, 20, "holiday.mo.establishment"), (12, 24, "Christmas Eve"), (12, 25, "Christmas Day"),
            (4, 5, "holiday.qingming"), (12, 22, "holiday.winter_solstice")] {
            add(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!, name)
        }
        let lunarNames = ["1-1": "holiday.cny1", "1-2": "holiday.cny2", "1-3": "holiday.cny3",
            "4-8": "holiday.buddha", "5-5": "holiday.dragon_boat", "8-16": "holiday.mid_autumn_next", "9-9": "holiday.double_ninth"]
        let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))!
        for offset in 0 ..< calendar.range(of: .day, in: .year, for: first)!.count {
            let date = calendar.date(byAdding: .day, value: offset, to: first)!
            let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
            if parts.isLeapMonth != true, let name = lunarNames["\(parts.month!)-\(parts.day!)"] { add(date, name) }
        }
        // 格里高利历复活节计算，耶稣受难日和复活节前日分别提前两天、一天。
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let value = h + l - 7 * m + 114
        let easter = calendar.date(from: DateComponents(year: year, month: value / 31, day: value % 31 + 1, hour: 12))!
        add(calendar.date(byAdding: .day, value: -2, to: easter)!, "Good Friday")
        add(calendar.date(byAdding: .day, value: -1, to: easter)!, "holiday.holy_saturday")
        return result.sorted { $0.date < $1.date }
    }
}
