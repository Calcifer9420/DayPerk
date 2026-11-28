import AppKit
import CryptoKit
import Foundation

struct AppDataArchive: Codable {
    let format: String
    let version: Int
    let createdAt: Date
    let preferences: Data
    let backgroundPNG: Data?
    let checksum: String
}

/// 原始备份只包含应用拥有的数据键，不导出系统设置、授权会话或凭据。
enum AppDataBackup {
    static let keys: Set<String> = [
        "launchAtLoginEnabled",
        WorkStatusController.storageKey,
        LeaveRequests.storageKey,
        "userProfile_current", "workSchedule_current", "manualWorkTrackingV1", "appLanguage", "appCurrency", "amountDecimalPlaces", "menuBarDecimalPlaces", "brewTheme", "brewBackground",
        "isPrivacyModeEnabled", "isMenuBarAmountHidden", "allDataLocked", "salaryDashboardProtected", "hideAmountWhenPaused", "statisticsShowcaseEnabled", SalaryAccessController.durationKey,
        "dayperkLeaveDays", "dayperkBaseSalary", "includeHousingFundInRate", "includeHousingFundInEstimate", "dayperkBreakMode", "dayperkBreakPeriods", "dayperkLinkCaffeine", "dayperkOvertimeDates", "dayperkDailyBreakMinutes", "dayperkDayStartMinute", "dayperkPaydayRule", "dayperkWorkRhythm", "dayperkAutomationRules", "dayperkOvertimeMultiplier", "dayperkWorkdayOverrides",
        "payrollFollowsCurrentMonth", "payrollPolicyV1", "payrollIncludeAnnualBonus", "payrollAnnualBonusBase", "payrollAnnualBonusMonths", "payrollDeductionEnabled", "payrollContributionBase", "payrollHousingFundBase", "payrollHousingFundRate", "payrollMonthlySpecialAdditionalDeduction", "payrollTaxMonth", "payrollTaxYear", "payrollEmploymentStartMonth", "payrollEmploymentStartYear", "payrollProrateAnnualBonus", "payrollAnnualBonusStartDate", "payrollIncomeRecords",
        "dayperkPayrollRegion", "dayperkRegionalPayInput", "dayperkRegionalPolicy", "dayperkRegionalDateOverrides", "dayperkWithdrawableBenefits", "dayperkWithdrawableBenefitsV2", "dayperkWorkTimeZone", "dayperkRegionalHolidays", "dayperkInternationalIncomeRecords", "chinaHolidayCalendarV1"
    ]
    static var backgroundURL: URL { UserDataStore.directory.appendingPathComponent("Appearance/background.png") }
    static func create(defaults: any UserDataPreferences = UserDataStore.shared, backgroundURL: URL = backgroundURL) throws -> AppDataArchive {
        if let store = defaults as? UserDataStore { try store.flush() }
        let values = defaults.dictionaryRepresentation().filter { keys.contains($0.key) }
        let preferences = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        let image = FileManager.default.fileExists(atPath: backgroundURL.path) ? try Data(contentsOf: backgroundURL) : nil
        return AppDataArchive(format: "DayPerk", version: 1, createdAt: Date(), preferences: preferences, backgroundPNG: image, checksum: checksum(preferences, image))
    }
    static func encoded(_ archive: AppDataArchive) throws -> Data { try JSONEncoder().encode(archive) }
    static func read(_ url: URL) throws -> AppDataArchive {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 100 * 1024 * 1024 else { throw invalid() }
        let archive: AppDataArchive
        do { archive = try JSONDecoder().decode(AppDataArchive.self, from: Data(contentsOf: url)) } catch { throw invalid() }
        _ = try validate(archive)
        return archive
    }
    static func validate(_ archive: AppDataArchive) throws -> [String: Any] {
        guard archive.format == "DayPerk", archive.version == 1, archive.preferences.count < 50 * 1024 * 1024,
              (archive.backgroundPNG?.count ?? 0) <= 50 * 1024 * 1024,
              archive.checksum == checksum(archive.preferences, archive.backgroundPNG),
              let values = try PropertyListSerialization.propertyList(from: archive.preferences, format: nil) as? [String: Any], Set(values.keys).isSubset(of: keys) else { throw invalid() }
        if let image = archive.backgroundPNG, NSImage(data: image) == nil { throw invalid() }
        func decode<T: Decodable>(_ key: String, _ type: T.Type) throws -> T? {
            guard let value = values[key] else { return nil }
            guard let bytes = value as? Data else { throw invalid() }
            do { return try JSONDecoder().decode(type, from: bytes) } catch { throw invalid() }
        }
        if let profile = try decode("userProfile_current", SalaryProfile.self) {
            guard profile.monthlySalary.isFinite, profile.monthlySalary >= 0, profile.monthlySalary < 1e12, (1 ... 366).contains(profile.workdaysPerMonth) else { throw invalid() }
        }
        _ = try decode("workSchedule_current", ReferenceSchedule.self)
        if let state = try decode("manualWorkTrackingV1", WorkTrackingState.self) {
            guard Set(state.days.map(\.id)).count == state.days.count else { throw invalid() }
            if let key = state.activeWorkday, ChinaHolidayCalendar.date(key) == nil { throw invalid() }
            for day in state.days {
                guard day.id.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                      [day.seconds, day.overtimeSeconds, day.earned].allSatisfy({ $0.isFinite && $0 >= 0 }),
                      [day.manualAdjustment, day.ratePerSecond, day.expectedIncome, day.overtimeMultiplier, day.grossRatePerSecond, day.referenceSeconds, day.registeredDailyGross].compactMap({ $0 }).allSatisfy(\.isFinite),
                      [day.settledAt, day.clockedInAt, day.scheduledStart, day.scheduledEnd].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw invalid() }
                if let start = day.scheduledStart, let end = day.scheduledEnd, end <= start { throw invalid() }
            }
        }
        _ = try decode("payrollPolicyV1", PayrollPolicy.self)
        _ = try decode("payrollIncomeRecords", [PayrollIncomeRecord].self)
        _ = try decode("dayperkInternationalIncomeRecords", [RegionalIncomeRecord].self)
        _ = try decode("dayperkRegionalPayInput", RegionalPayInput.self)
        if let policy = try decode("dayperkRegionalPolicy", RegionalPayrollPolicy.self) { try policy.validate() }
        if let benefits = try decode("dayperkWithdrawableBenefits", [String: WithdrawableBenefit].self) { for value in benefits.values { try value.validate() } }
        if let lists = try decode("dayperkWithdrawableBenefitsV2", [String: [WithdrawableBenefit]].self) {
            for (key, values) in lists {
                guard let raw = key.split(separator: ":").first, let region = PayrollRegion(rawValue: String(raw)) else { throw CocoaError(.propertyListReadCorrupt) }
                try WithdrawableBenefit.validate(values, region: region)
            }
        }
        _ = try decode("dayperkRegionalDateOverrides", [String: [String: Bool]].self)
        _ = try decode("dayperkRegionalHolidays", [RegionalHolidaySnapshot].self)
        _ = try decode("chinaHolidayCalendarV1", ChinaHolidayCache.self)
        _ = try decode("dayperkWorkdayOverrides", [String: Bool].self)
        if let rates = try decode("dayperkOvertimeDates", [String: Double].self), !rates.values.allSatisfy(OvertimeRateInput.isValid) { throw invalid() }
        if let days = try decode(LeaveLedger.storageKey, [String: LeaveDay].self) { try LeaveLedger.validate(days) }
        if let requests = try decode(LeaveRequests.storageKey, [LeaveRequest].self) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = (values["dayperkWorkTimeZone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current
            try LeaveRequests.validate(requests, calendar: calendar)
        }
        if let rhythm = try decode("dayperkWorkRhythm", WorkRhythm.self) { try rhythm.validate() }
        if let rules = try decode("dayperkAutomationRules", WorkAutomationRules.self) { try rules.validate() }
        if let statuses = try decode(WorkStatusController.storageKey, WorkStatusData.self) { try statuses.validate() }
        if let value = values[SalaryAccessController.durationKey] {
            guard let seconds = value as? Int, (0 ... SalaryAccessController.maximumDuration).contains(seconds) else { throw invalid() }
        }
        _ = try decode("dayperkPaydayRule", PaydayRule.self)
        _ = try decode("dayperkBreakPeriods", [WorkBreak].self)
        _ = try decode("brewBackground", BackgroundPreferences.self)
        for (key, value) in values {
            if let n = value as? NSNumber, !n.doubleValue.isFinite { throw invalid() }
            if key == "dayperkWorkTimeZone", let zone = value as? String, TimeZone(identifier: zone) == nil { throw invalid() }
        }
        return values
    }
    static func restore(_ archive: AppDataArchive, defaults: any UserDataPreferences = UserDataStore.shared, domain: String = Bundle.main.bundleIdentifier!, backgroundURL: URL = backgroundURL) throws {
        let values = try validate(archive)
        let previousImage = FileManager.default.fileExists(atPath: backgroundURL.path) ? try Data(contentsOf: backgroundURL) : nil
        // 所有可能失败的文件操作先完成；随后一次替换应用数据域，保留系统和无关键。
        if let image = archive.backgroundPNG {
            try FileManager.default.createDirectory(at: backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.write(to: backgroundURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: backgroundURL.path) {
            try FileManager.default.removeItem(at: backgroundURL)
        }
        var domainValues = defaults.persistentDomain(forName: domain) ?? [:]
        domainValues = domainValues.filter { !keys.contains($0.key) }
        domainValues.merge(values, uniquingKeysWith: { _, imported in imported })
        let previousDomain = defaults.persistentDomain(forName: domain) ?? [:]
        do {
            if let store = defaults as? UserDataStore { try store.replace(with: domainValues) }
            else {
                defaults.setPersistentDomain(domainValues, forName: domain)
                guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            if let previousImage { try previousImage.write(to: backgroundURL, options: .atomic) }
            else if FileManager.default.fileExists(atPath: backgroundURL.path) { try FileManager.default.removeItem(at: backgroundURL) }
            if !(defaults is UserDataStore) { defaults.setPersistentDomain(previousDomain, forName: domain); defaults.synchronize() }
            throw error
        }
    }
    private static func checksum(_ preferences: Data, _ image: Data?) -> String {
        var hash = SHA256(); hash.update(data: preferences); if let image { hash.update(data: image) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func invalid() -> DayPerkInputError { DayPerkInputError(message: L10n.text("backup.invalid")) }
}
