import Combine
import Foundation

struct ChinaHolidayDay: Codable, Equatable, Identifiable {
    var name: String
    var date: String
    var isOffDay: Bool
    var id: String {
        date
    }
}

struct ChinaHolidayPlan: Codable, Equatable {
    var year: Int
    var papers: [String]
    var days: [ChinaHolidayDay]

    func validated(for requestedYear: Int) throws -> ChinaHolidayPlan {
        guard year == requestedYear, !days.isEmpty, !papers.isEmpty,
              papers.allSatisfy({ source in
                  guard let url = URL(string: source), let host = url.host?.lowercased() else { return false }
                  return url.scheme == "https" && (host == "gov.cn" || host.hasSuffix(".gov.cn"))
              }), Set(days.map(\.date)).count == days.count else { throw ChinaHolidayError.invalidData }
        for day in days {
            guard let date = ChinaHolidayCalendar.date(day.date), !day.name.isEmpty else { throw ChinaHolidayError.invalidData }
            let parts = ChinaHolidayCalendar.calendar.dateComponents([.year, .month], from: date)
            guard parts.year == year || (parts.year == year - 1 && parts.month == 12) else { throw ChinaHolidayError.invalidData }
        }
        return self
    }
}

enum ChinaHolidayError: LocalizedError {
    case invalidData, unavailable(Int), server(Int)
    var errorDescription: String? {
        switch self {
        case .invalidData: return L10n.text("ui.incomplete_holiday_data_or_invalid.fdfc8b11")
        case let .unavailable(year): return L10n.format("ui.1.d4265641", String(describing: year))
        case let .server(status): return L10n.format("ui.1.fa282628", String(describing: status))
        }
    }
}

struct ChinaHolidayCache: Codable {
    var plans: [Int: ChinaHolidayPlan] = [:]
    var imported: [String: Bool] = [:]
    var updatedAt: Date?
}

/// 只下载公开放假计划；本机工时和自定义日期例外不会上传。
@MainActor final class ChinaHolidayCalendar: ObservableObject {
    static let shared = ChinaHolidayCalendar()
    nonisolated static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }

    @Published private(set) var cache: ChinaHolidayCache
    @Published private(set) var refreshing = false
    @Published private(set) var result = ""
    @Published private(set) var hasRefreshFailures = false
    private let defaults: any UserDataPreferences
    private let cacheKey = "chinaHolidayCalendarV1"

    init(defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        cache = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(ChinaHolidayCache.self, from: $0) } ?? ChinaHolidayCache()
        cache.plans = cache.plans.filter { (try? $0.value.validated(for: $0.key)) != nil }
        for plan in Self.bundledPlans() where cache.plans[plan.year] == nil {
            cache.plans[plan.year] = plan
            for day in plan.days where cache.imported[day.date] == nil {
                cache.imported[day.date] = !day.isOffDay
            }
        }
    }

    func reloadFromStorage() { cache = ChinaHolidayCalendar(defaults: defaults).cache }

    nonisolated static func bundledPlans(bundle: Bundle = .main) -> [ChinaHolidayPlan] {
        [2026, 2027].compactMap { year in
            guard let url = bundle.url(forResource: "holiday-\(year)", withExtension: "json")
                ?? bundle.url(forResource: "holiday-\(year)", withExtension: "json", subdirectory: "HolidayPlans"),
                let data = try? Data(contentsOf: url),
                let plan = try? JSONDecoder().decode(ChinaHolidayPlan.self, from: data) else { return nil }
            return try? plan.validated(for: year)
        }
    }

    nonisolated static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    nonisolated static func date(_ key: String) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), self.key(date) == key else { return nil }
        return date
    }

    func day(_ date: Date) -> ChinaHolidayDay? {
        let key = Self.key(date)
        return cache.plans.keys.sorted().compactMap { cache.plans[$0]?.days.first { $0.date == key } }.last
    }

    /// 仅替换上次导入且未被用户改动的日期；自定义例外和其他年份保持不变。
    nonisolated static func merging(_ plans: [ChinaHolidayPlan], into overrides: [String: Bool], imported: [String: Bool]) -> (overrides: [String: Bool], imported: [String: Bool]) {
        var updated = overrides
        var managed = imported
        let years = Set(plans.map(\.year))
        let newDays = plans.sorted { $0.year < $1.year }.flatMap(\.days)
        let affected = Set(newDays.map(\.date)).union(imported.keys.filter { key in Int(key.prefix(4)).map(years.contains) ?? false })
        for key in affected {
            if let old = imported[key], updated[key] == old {
                updated.removeValue(forKey: key)
            }
            managed.removeValue(forKey: key)
        }
        for day in newDays {
            if updated[day.date] == nil {
                let working = !day.isOffDay
                updated[day.date] = working
                managed[day.date] = working
            }
        }
        return (updated, managed)
    }

    func refresh(overrides: [String: Bool], now: Date = Date(), currentOverrides: (() -> [String: Bool])? = nil) async -> [String: Bool] {
        guard !refreshing else { return overrides }
        refreshing = true
        defer { refreshing = false }
        let year = Self.calendar.component(.year, from: now)
        var succeeded: [ChinaHolidayPlan] = []
        var messages: [String] = []
        for target in [year, year + 1] {
            do {
                let plan = try await Self.fetch(target)
                succeeded.append(plan)
                messages.append(L10n.format("ui.1_2.98b3862d", String(describing: target), String(describing: plan.days.count)))
            } catch { messages.append("\(target)：" + error.localizedDescription) }
        }
        hasRefreshFailures = succeeded.count < 2
        if !succeeded.isEmpty {
            for plan in succeeded {
                cache.plans[plan.year] = plan
            }
            let merged = Self.merging(succeeded, into: currentOverrides?() ?? overrides, imported: cache.imported)
            cache.imported = merged.imported
            cache.updatedAt = Date()
            if let data = try? JSONEncoder().encode(cache) {
                defaults.set(data, forKey: cacheKey)
            }
            result = messages.joined(separator: "\n")
            return merged.overrides
        }
        result = messages.joined(separator: "\n")
        return overrides
    }

    private static func fetch(_ year: Int) async throws -> ChinaHolidayPlan {
        let endpoint = URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChinaHolidayError.invalidData }
        if http.statusCode == 404 {
            throw ChinaHolidayError.unavailable(year)
        }
        guard http.statusCode == 200 else { throw ChinaHolidayError.server(http.statusCode) }
        guard data.count < 500_000 else { throw ChinaHolidayError.invalidData }
        return try JSONDecoder().decode(ChinaHolidayPlan.self, from: data).validated(for: year)
    }
}
