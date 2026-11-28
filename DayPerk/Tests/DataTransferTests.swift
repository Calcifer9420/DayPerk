import AppKit
import Foundation
import Testing
@testable import DayPerk

struct DataTransferTests {
    @MainActor @Test func transferAuthenticatesOnDemandAndReusesTheTenMinuteGrant() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.transfer-auth." + UUID().uuidString))
        var requests = 0; var actions = 0
        let access = SalaryAccessController(defaults: defaults) { _, done in requests += 1; done(true) }
        access.authorizeDataTransfer { actions += 1 }
        access.authorizeDataTransfer { actions += 1 }
        #expect(requests == 1 && actions == 2)
        access.revokeAuthorization()
        access.authorizeDataTransfer { actions += 1 }
        #expect(requests == 2 && actions == 3)
        access.lockAllData()
        access.authorizeDataTransfer { actions += 1 }
        #expect(requests == 2 && actions == 3)
    }

    @MainActor @Test func cancelledTransferAuthenticationCannotOpenFileActions() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.dayperk.tests.transfer-denied." + UUID().uuidString))
        var actions = 0
        let access = SalaryAccessController(defaults: defaults) { _, done in done(false) }
        access.authorizeDataTransfer { actions += 1 }
        #expect(actions == 0 && !access.settingsUnlocked)
    }
    @Test func archiveRoundTripRestoresEveryOwnedValueAndKeepsUnrelatedSettings() throws {
        let name = "app.dayperk.tests.backup." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent("background.png")
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(bitmap.representation(using: .png, properties: [:])); try image.write(to: imageURL)
        defaults.set(11_454, forKey: "dayperkBaseSalary"); defaults.set("ja", forKey: "appLanguage")
        defaults.set("JP", forKey: "dayperkPayrollRegion"); defaults.set("Asia/Tokyo", forKey: "dayperkWorkTimeZone")
        defaults.set("do-not-export", forKey: "unrelatedCredential")
        var state = WorkTrackingState(); state.days = [WorkDayTotal(id: "2026-11-24", seconds: 500, earned: 123, ratePerSecond: 0.246, expectedIncome: 200, currencyCode: "JPY")]
        defaults.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        let source = try AppDataBackup.create(defaults: defaults, backgroundURL: imageURL)
        let encoded = try AppDataBackup.encoded(source)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("do-not-export"))
        let decoded = try JSONDecoder().decode(AppDataArchive.self, from: encoded)
        let before = try AppDataBackup.validate(decoded)
        defaults.set(9, forKey: "dayperkBaseSalary"); defaults.set("en", forKey: "appLanguage"); defaults.set(true, forKey: "dayperkLinkCaffeine")
        try AppDataBackup.restore(decoded, defaults: defaults, domain: name, backgroundURL: imageURL)
        let after = try AppDataBackup.validate(AppDataBackup.create(defaults: defaults, backgroundURL: imageURL))
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
        #expect(defaults.string(forKey: "unrelatedCredential") == "do-not-export")
        #expect(defaults.object(forKey: "dayperkLinkCaffeine") == nil)
        #expect(try Data(contentsOf: imageURL) == image)
        let loaded = try JSONDecoder().decode(WorkTrackingState.self, from: #require(defaults.data(forKey: "manualWorkTrackingV1")))
        #expect(loaded == state)
    }

    @Test func corruptAndNewerBackupsDoNotMutateExistingData() throws {
        let name = "app.dayperk.tests.invalid." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name)); defaults.set(11454, forKey: "dayperkBaseSalary")
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let good = try AppDataBackup.create(defaults: defaults, backgroundURL: imageURL)
        let corrupt = AppDataArchive(format: good.format, version: 1, createdAt: good.createdAt, preferences: good.preferences + Data([1]), backgroundPNG: nil, checksum: good.checksum)
        #expect(throws: (any Error).self) { try AppDataBackup.restore(corrupt, defaults: defaults, domain: name, backgroundURL: imageURL) }
        let newer = AppDataArchive(format: good.format, version: 99, createdAt: good.createdAt, preferences: good.preferences, backgroundPNG: nil, checksum: good.checksum)
        #expect(throws: (any Error).self) { try AppDataBackup.restore(newer, defaults: defaults, domain: name, backgroundURL: imageURL) }
        #expect(defaults.double(forKey: "dayperkBaseSalary") == 11454)
    }

    @Test func restoredActiveSnapshotKeepsEvenShortRecordedTimeWithoutBackfilling() throws {
        let name = "app.dayperk.tests.restore." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let day = WorkDayTotal(id: "2026-11-24", seconds: 5, earned: 10)
        var state = WorkTrackingState(); state.days = [day]; state.isWorking = true
        state.sessionStartedAt = Date(timeIntervalSince1970: 100); state.lastTick = Date(timeIntervalSince1970: 105); state.sessionBaseline = []
        defaults.set(try JSONEncoder().encode(state), forKey: "manualWorkTrackingV1")
        let controller = WorkTrackingController(defaults: defaults, observeSystem: false, restoringBackup: true)
        #expect(controller.state.days == [day]); #expect(controller.state.isWorking)
        #expect(controller.state.lastTick! > Date().addingTimeInterval(-2))
        #expect(controller.state.sessionBaseline == nil)
        controller.discardForRestore()
    }

    @Test func monthExportIncludesEveryDateAndOneReconciledTotal() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = c.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let report = WorkReport.make(days: [WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 100)], containing: date, period: .month, calendar: c, asOf: date, expectedIncome: { $0.seconds > 0 ? 150 : 0 })
        let file = ReportExcelExport.data(report: report, currency: "CAD", calendar: c, locale: Locale(identifier: "fr_CA"))
        let text = String(decoding: file, as: UTF8.self)
        #expect(report.days.count == 30)
        #expect(text.contains("SUM(H2:H31)")); #expect(text.contains("<v>50.0</v>"))
        try file.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("DayPerk-month-export-verification.xlsx"))
    }

    @Test func excelContainsNumericAmountsDurationsAndCachedTotals() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let report = WorkReport.make(days: [WorkDayTotal(id: "2026-11-23", seconds: 3600, overtimeSeconds: 600, earned: 11454.25, referenceSeconds: 1800, currencyCode: "USD")], containing: date, period: .week, calendar: calendar, asOf: date, expectedIncome: { $0.seconds > 0 ? 12000 : 0 })
        let file = ReportExcelExport.data(report: report, currency: "USD", calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(file.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        let text = String(decoding: file, as: UTF8.self)
        #expect(text.contains("<v>11454.25</v>")); #expect(text.contains("SUM(H2:H8)")); #expect(text.contains("<v>545.75</v>"))
        #expect(text.contains("[hh]:mm:ss")); #expect(text.contains("<t xml:space=\"preserve\">USD</t>"))
        #expect(ReportExcelExport.xml("=SUM(A1) & <data>\u{1}") == "=SUM(A1) &amp; &lt;data&gt;")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("DayPerk-week-export-verification.xlsx")
        try file.write(to: destination)
    }

    @Test func exportedTableStartsWithColumnNamesAndFitsEveryColumn() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let report = WorkReport.make(days: [WorkDayTotal(id: "2026-11-23", seconds: 3600, earned: 100.0000000001)], containing: date, period: .week, calendar: calendar, expectedIncome: { _ in 100 })
        let text = String(decoding: ReportExcelExport.data(report: report, currency: "CNY", calendar: calendar, locale: Locale(identifier: "zh_CN")), as: UTF8.self)
        #expect(text.contains("topLeftCell=\"A2\""))
        #expect(text.contains("autoFilter ref=\"A1:L8\""))
        #expect(text.contains("max=\"12\" width=\"25\""))
        #expect(text.contains("<headerFooter><oddHeader>"))
        #expect(text.contains("<c r=\"H2\" s=\"3\"><v>0.0</v>"))
        #expect(!text.contains("<c r=\"A1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">DayPerk"))
    }

    @Test func futureBalancesAndRecalculatedExcelTotalsStayZero() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26))!
        let report = WorkReport.make(days: [WorkDayTotal(id: "2026-11-26", seconds: 3600, earned: 100)], containing: today, period: .week, calendar: calendar, asOf: today,
                                     expectedIncome: { $0.id <= "2026-11-27" ? 200 : 0 })
        let file = ReportExcelExport.data(report: report, currency: "CNY", calendar: calendar, locale: Locale(identifier: "zh_CN"))
        let text = String(decoding: file, as: UTF8.self)
        #expect(report.expectedIncome == 800 && report.balance == 700)
        #expect(text.contains("<c r=\"G6\" s=\"3\"><v>0.0</v>"))
        #expect(text.contains("<c r=\"H6\" s=\"3\"><v>0.0</v>"))
        #expect(text.contains("<c r=\"F9\" s=\"3\"><f>SUM(F2:F8)</f><v>800.0</v>"))
        #expect(text.contains("<c r=\"H9\" s=\"4\"><f>SUM(H2:H8)</f><v>700.0</v>"))
        try file.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("DayPerk-future-export-verification.xlsx"))

        let future = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27))!
        let futureReport = WorkReport.make(days: [], containing: future, period: .day, calendar: calendar, asOf: today, expectedIncome: { _ in 200 })
        let futureText = String(decoding: ReportExcelExport.data(report: futureReport, currency: "CNY", calendar: calendar, locale: Locale(identifier: "zh_CN")), as: UTF8.self)
        #expect(futureReport.expectedIncome == 0 && futureReport.balance == 0)
        #expect(futureText.contains("<c r=\"F3\" s=\"3\"><f>SUM(F2:F2)</f><v>0.0</v>"))
    }

    @Test func excelUsesExpectedActualAndSignedTimeWithReconciledNumericTotals() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26))!
        let records = [WorkDayTotal(id: "2026-11-23", seconds: 30765, overtimeSeconds: 3600, earned: 1746.38, referenceSeconds: 30600),
                       WorkDayTotal(id: "2026-11-24", seconds: 25725, earned: 1461.83, referenceSeconds: 30600)]
        let report = WorkReport.make(days: records, containing: today, period: .week, calendar: calendar, asOf: today,
            expectedIncome: { $0.id <= "2026-11-27" ? 1739.39 : 0 },
            expectedWorkSeconds: { $0.id <= "2026-11-27" ? 30600 : 0 })
        let file = ReportExcelExport.data(report: report, currency: "CNY", calendar: calendar, locale: Locale(identifier: "zh_CN"))
        let text = String(decoding: file, as: UTF8.self)
        #expect(text.contains("<c r=\"C1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">" + L10n.text("report.expected_work_time")))
        #expect(text.contains("<c r=\"F1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">" + L10n.text("ui.expected_income.7b122310")))
        #expect(text.contains("<c r=\"G1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">" + L10n.text("ui.time_value.a472b6c3")))
        #expect(!text.contains(L10n.text("ui.registered_overtime.694d1416")))
        #expect(text.contains("<workbookPr date1904=\"1\"/>") && text.contains("+[hh]:mm:ss;-[hh]:mm:ss;"))
        let styles = try #require(text.components(separatedBy: "<cellXfs count=\"8\">").last?.components(separatedBy: "</cellXfs>").first)
        #expect(styles.components(separatedBy: "horizontal=\"center\" vertical=\"center\"").count - 1 == 8)
        #expect(text.contains("<c r=\"D2\" s=\"2\"><v>\(30765.0 / 86400)</v>"))
        #expect(text.contains("<c r=\"E2\" s=\"6\"><f>D2-C2</f><v>\(165.0 / 86400)</v>"))
        #expect(text.contains("<c r=\"E3\" s=\"7\"><f>D3-C3</f><v>\(-4875.0 / 86400)</v>"))
        #expect(text.contains("<c r=\"E6\" s=\"2\"><f>D6-C6</f><v>0.0</v>"))
        #expect(text.contains("<c r=\"E9\" s=\"7\"><f>SUM(E2:E8)</f><v>\(-65910.0 / 86400)</v>"))
        #expect(report.workSeconds == 56490 && report.expectedWorkSeconds == 122400 && report.timeDifferenceSeconds == -65910)
        try file.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("DayPerk-time-difference-verification.xlsx"))
    }
}
