import Combine
import Foundation

struct RegionalHoliday: Codable, Identifiable, Equatable {
    var date: String
    var name: String
    var localName: String
    var countryCode: String
    var counties: [String]?
    var types: [String]
    var id: String { date + name }
}

struct RegionalHolidaySnapshot: Codable {
    var country: String
    var year: Int
    var fetchedAt: Date
    var holidays: [RegionalHoliday]
}

/// 下载内容只有公共国家、年份和日期，不上传工时或薪酬。
final class RegionalHolidayCalendar: ObservableObject {
    static let shared = RegionalHolidayCalendar()
    @Published private(set) var snapshots: [RegionalHolidaySnapshot]
    @Published private(set) var refreshing = false
    @Published private(set) var errorMessage = ""
    private let defaults: any UserDataPreferences

    init(defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        let stored = defaults.data(forKey: "dayperkRegionalHolidays").flatMap { try? JSONDecoder().decode([RegionalHolidaySnapshot].self, from: $0) } ?? []
        let bundled = Bundle.main.url(forResource: "RegionalHolidays", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([RegionalHolidaySnapshot].self, from: $0) } ?? []
        let macau = [2026, 2027].compactMap { year in
            (try? MacauPublicHolidays.days(year: year)).map { RegionalHolidaySnapshot(country: "MO", year: year, fetchedAt: Date(timeIntervalSince1970: 0), holidays: $0) }
        }
        snapshots = stored + (bundled + macau).filter { item in !stored.contains { $0.country == item.country && $0.year == item.year } }
    }

    func reloadFromStorage() { snapshots = RegionalHolidayCalendar(defaults: defaults).snapshots }

    func days(country: String, subdivision: String) -> [RegionalHoliday] {
        snapshots.filter { $0.country == country }.flatMap(\.holidays).filter { day in
            day.types.contains("Public") && (day.counties == nil || day.counties?.contains(subdivision) == true)
                // Nager 将南坎特伯雷与基督城共用省码；基督城不放南部的 Dominion Day。
                && !(country == "NZ" && subdivision == "NZ-CAN" && day.localName == "Dominion Day")
        }
    }

    func overrides(country: String, subdivision: String, manual: [String: Bool]) -> [String: Bool] {
        var value = Dictionary(days(country: country, subdivision: subdivision).map { ($0.date, false) }, uniquingKeysWith: { a, _ in a })
        manual.forEach { value[$0.key] = $0.value }
        return value
    }

    @MainActor func refresh(country: String, calendar: Calendar, now: Date = Date()) async {
        guard !refreshing, let provider = PayrollCatalog.bundled.holidayProviders.first(where: { $0.country == country && ["nager", "france", "macau"].contains($0.kind) }) else { return }
        refreshing = true; errorMessage = ""
        defer { refreshing = false }
        let year = calendar.component(.year, from: now)
        var failures: [String] = []
        for target in [year, year + 1] {
            do {
                let days: [RegionalHoliday]
                if provider.kind == "macau" {
                    days = try MacauPublicHolidays.days(year: target)
                } else if provider.kind == "france" {
                    let template = provider.url.replacingOccurrences(of: "{year}", with: String(target))
                    let national = try await Self.download(template.replacingOccurrences(of: "{zone}", with: "metropole"))
                    let regional = try await Self.download(template.replacingOccurrences(of: "{zone}", with: "alsace-moselle"))
                    days = try Self.frenchHolidays(national: national, alsaceMoselle: regional)
                } else {
                    let data = try await Self.download(provider.url.replacingOccurrences(of: "{year}", with: String(target)))
                    days = try JSONDecoder().decode([RegionalHoliday].self, from: data)
                }
                try Self.validate(days, country: country, year: target)
                snapshots.removeAll { $0.country == country && $0.year == target }
                snapshots.append(RegionalHolidaySnapshot(country: country, year: target, fetchedAt: now, holidays: days))
            } catch { failures.append("\(target): \(error.localizedDescription)") }
        }
        if let data = try? JSONEncoder().encode(snapshots) { defaults.set(data, forKey: "dayperkRegionalHolidays") }
        errorMessage = failures.joined(separator: "\n")
    }

    private static func download(_ address: String) async throws -> Data {
        guard let url = URL(string: address), url.scheme == "https" else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw URLError(.badServerResponse) }
        return data
    }

    static func frenchHolidays(national: Data, alsaceMoselle: Data) throws -> [RegionalHoliday] {
        let decoder = JSONDecoder()
        let common = try decoder.decode([String: String].self, from: national)
        let regional = try decoder.decode([String: String].self, from: alsaceMoselle)
        guard !common.isEmpty, !regional.isEmpty, common.allSatisfy({ regional[$0.key] == $0.value }) else {
            throw DayPerkInputError(message: L10n.text("ui.invalid_holiday_data_the_previous_c.79c23bfd"))
        }
        return (common.map { RegionalHoliday(date: $0.key, name: $0.value, localName: $0.value, countryCode: "FR", types: ["Public"]) }
            + regional.filter { common[$0.key] == nil }.map {
                RegionalHoliday(date: $0.key, name: $0.value, localName: $0.value, countryCode: "FR", counties: ["FR-57", "FR-67", "FR-68"], types: ["Public"])
            }).sorted { $0.date < $1.date }
    }

    nonisolated static func validate(_ days: [RegionalHoliday], country: String, year: Int) throws {
        guard !days.isEmpty, days.count < 1000, days.allSatisfy({ day in
            day.countryCode == country && day.date.hasPrefix("\(year)-") && ChinaHolidayCalendar.date(day.date) != nil && !day.name.isEmpty
        }) else { throw DayPerkInputError(message: L10n.text("ui.invalid_holiday_data_the_previous_c.79c23bfd")) }
    }
}
