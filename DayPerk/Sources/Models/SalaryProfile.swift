import Foundation

/// 个人资料的数据格式：字段名保持兼容，防止更新后丢失既有账本。
struct SalaryProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var currency = "CNY"
    var monthlySalary: Double
    var workdaysPerMonth: Int
    var createdAt = Date()
    var updatedAt = Date()

    init(name: String, monthlySalary: Double, workdaysPerMonth: Int, currency: String = "CNY") {
        (self.name, self.monthlySalary, self.workdaysPerMonth, self.currency) = (name, monthlySalary, workdaysPerMonth, currency)
    }
}

struct ReferenceSchedule: Codable, Identifiable {
    var id = UUID()
    var startTime: Date
    var endTime: Date
    var workdays: Set<Weekday> = Set(Weekday.allCases.filter { (2 ... 6).contains($0.calendarWeekday) })
    var isActive = true
    var createdAt = Date()
    var updatedAt = Date()
}

enum Weekday: String, Codable, CaseIterable {
    case monday = "Monday", tuesday = "Tuesday", wednesday = "Wednesday", thursday = "Thursday"
    case friday = "Friday", saturday = "Saturday", sunday = "Sunday"

    var calendarWeekday: Int { (Self.allCases.firstIndex(of: self)! + 1) % 7 + 1 }
}

extension Date {
    static func createTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
