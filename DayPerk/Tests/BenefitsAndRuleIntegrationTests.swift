import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DayPerk

/// 涉及模型单例和原生截图的检查只在独立文档宿主中运行。
struct BenefitsAndRuleIntegrationTests {
    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier == "app.dayperk.documentation.interaction"))
    func incomeCanBeEnteredAndSavedThroughTheNativeEditor() async throws {
        let seed = try LocalPreviewMode.loadSeed()
        try LocalPreviewMode.prepare(seed)
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        try LocalPreviewMode.apply(seed, to: model)
        LocalizationManager.shared.setLanguage(.chinese)
        model.access.unlockSettings()
        let content = Form { WithdrawableBenefitsSection(model: model, region: .china, currency: "CNY") }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle())
            .environment(\.locale, LocalizationManager.shared.currentLocale).actionToastHost()
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 790, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "薪咖交互测试"; window.isReleasedWhenClosed = false; window.contentView = hosting
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close(); model.tracking.shutdown() }
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if model.withdrawableBenefits.contains(where: { $0.name == "交互验证" && $0.monthlyAmount == 400 }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("原生编辑器未保存输入的名称与金额")
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier == "app.dayperk.documentation.benefits"))
    func savedRulesAndExtraIncomeSurviveReopeningAndApplyToday() throws {
        let seed = try LocalPreviewMode.loadSeed()
        try LocalPreviewMode.prepare(seed)
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        try LocalPreviewMode.apply(seed, to: model)
        model.access.unlockSettings()
        var civil = model.configuration
        civil.dayStartMinute = 0
        let civilToday = model.workCalendar.startOfDay(for: Date())
        civil.dateOverrides[WorkPlan.dayKey(civilToday, calendar: model.workCalendar)] = true
        civil.dateOverrides[WorkPlan.dayKey(model.workCalendar.date(byAdding: .day, value: -7, to: civilToday)!, calendar: model.workCalendar)] = true
        try model.saveConfiguration(civil)
        try model.saveBenefits([], region: .china, currency: "CNY")
        let today = model.today.id
        let before = model.tracking.state.days.filter { $0.id < today }
        let businessDate = model.tracking.plan.businessDayStart(for: Date(), calendar: model.workCalendar)
        let weekday = model.workCalendar.component(.weekday, from: businessDate)
        let dailyIncome = model.expectedIncome(for: model.today)
        let normalRate = model.tracking.plan.ratePerSecond
        var rule = WorkScheduleRule(name: "当日规则", weekdays: [weekday], schedule: .init(startMinute: 540, endMinute: 1020, breakMinutes: 60))
        try model.saveScheduleRules([rule])
        rule.effectiveFromDay = WorkPlan.dayKey(Date(), calendar: model.workCalendar)
        #expect(model.tracking.plan.referenceSeconds(for: today) == 7 * 3600)
        #expect(model.configuration.referenceMinutes(for: today) == 7 * 60)
        #expect(model.expectedIncome(for: model.today) == dailyIncome)
        #expect(model.tracking.plan.ratePerSecond > normalRate)
        #expect(model.tracking.state.days.filter { $0.id < today } == before)
        let persisted = try JSONDecoder().decode(WorkRhythm.self, from: #require(UserDataStore.shared.data(forKey: "dayperkWorkRhythm")))
        #expect(persisted.scheduleRules == [rule])
        let pastDate = try #require(model.workCalendar.date(byAdding: .day, value: -7, to: businessDate))
        let pastKey = WorkPlan.dayKey(pastDate, calendar: model.workCalendar)
        let originalDay = try #require(model.tracking.state.days.first { $0.id == pastKey })
        #expect(!rule.matches(pastKey) && rule.matchesRecurrence(pastKey))
        #expect(model.rhythm.daySchedules?[pastKey] == nil)
        #expect(model.businessPlan.schedule(for: pastKey) != rule.schedule)
        let covered = try model.correctWorkSchedules(from: pastDate, through: pastDate, ruleID: rule.id)
        #expect(covered == 1)
        let corrected = try #require(model.tracking.state.days.first { $0.id == pastKey })
        #expect(corrected.seconds == originalDay.seconds && corrected.expectedIncome == originalDay.expectedIncome)
        #expect(corrected.referenceSeconds == 7 * 3600 && model.rhythm.daySchedules?[pastKey] == rule.schedule)
        let restoredRhythm = model.rhythm
        let mismatch = try #require(model.workCalendar.date(byAdding: .day, value: -6, to: businessDate))
        #expect(throws: DayPerkInputError.self) { try model.correctWorkSchedules(from: mismatch, through: mismatch, ruleID: rule.id) }
        #expect(model.rhythm == restoredRhythm)
        let missingDate = try #require(model.workCalendar.date(byAdding: .day, value: -200, to: businessDate))
        let missingKey = WorkPlan.dayKey(missingDate, calendar: model.workCalendar)
        let newPreview = model.previewWorkCorrection(missingKey, seconds: 3600)
        try model.correctWorkTime(missingKey, seconds: 3600)
        let addedRecord = try #require(model.tracking.state.days.first { $0.id == missingKey })
        #expect(addedRecord.seconds == 3600 && addedRecord.earned == newPreview.earned && addedRecord.ratePerSecond == newPreview.ratePerSecond)
        let loaded = UserDataStore(directory: UserDataStore.directory)
        #expect(!LocalPreviewMode.requiresInitialSeed(defaults: loaded, bundleID: LocalPreviewMode.bundleIdentifier))

        let extra = WithdrawableBenefit(name: "人才补贴", monthlyAmount: 400, includeInRate: false)
        let fund = WithdrawableBenefit(name: "公积金提取", monthlyAmount: 600, includeInRate: false)
        let rate = model.tracking.plan.ratePerSecond
        let net = model.breakdown.netMonthlyIncome
        let tax = model.breakdown.individualIncomeTax
        try model.saveBenefits([fund, extra], region: .china, currency: "CNY")
        #expect(model.benefitForEstimate == 1_000)
        #expect(model.tracking.plan.ratePerSecond == rate)
        #expect(model.breakdown.netMonthlyIncome == net && model.breakdown.individualIncomeTax == tax)
        model.updateBenefitOptions(id: extra.id, includeInRate: true)
        #expect(model.tracking.plan.ratePerSecond > rate)
        #expect(model.salaryFormulaRows.contains { $0.label == extra.name && $0.isUserProvidedLabel })
        let reopened = RegionalPayrollSettings(defaults: UserDataStore(directory: UserDataStore.directory))
        #expect(reopened.withdrawableBenefits(region: .china, currency: "CNY").count == 2)

        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LocalPreview/IncomeReview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.chinese, .english] {
            LocalizationManager.shared.setLanguage(language)
            for region in [PayrollRegion.china, .singapore] {
                let currency = region == .china ? "CNY" : "SGD"
                if region == .singapore {
                    try model.saveBenefits([.init(name: language == .chinese ? "可提取储蓄" : "Available savings", monthlyAmount: 1234.56),
                        .init(name: L10n.text("benefits.demo_item"), monthlyAmount: 320, includeInRate: false)], region: region, currency: currency)
                }
                let content = Form { WithdrawableBenefitsSection(model: model, region: region, currency: currency) }
                    .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                    .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle())
                    .environment(\.locale, LocalizationManager.shared.currentLocale)
                let view = NSHostingView(rootView: content)
                view.frame = CGRect(x: 0, y: 0, width: 790, height: 290)
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view; window.orderFront(nil); view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("multiple-benefits-" + region.rawValue + "-" + language.rawValue + ".png"))
                window.orderOut(nil)
            }
        }
        let singapore = try #require(PayrollCatalog.bundled.policies.first { $0.id == "sg-singapore" })
        var input = RegionalPayInput(); input.amount = 20_000; input.frequency = .monthly; input.cpfStatus = "foreigner"
        try model.saveRegionalSettings(region: .singapore, input: input, policy: singapore, timeZoneID: "Asia/Singapore")
        var foreign = model.configuration; foreign.rhythm.scheduleRules = nil
        foreign.dateOverrides[model.today.id] = true
        try model.saveConfiguration(foreign)
        let foreignDay = model.today.id
        let foreignIncome = model.expectedIncome(for: model.today)
        let foreignNet = model.breakdown.netMonthlyIncome
        let foreignRate = model.tracking.plan.ratePerSecond
        let foreignBusinessDate = model.tracking.plan.businessDayStart(for: Date(), calendar: model.workCalendar)
        let foreignWeekday = model.workCalendar.component(.weekday, from: foreignBusinessDate)
        var foreignRule = WorkScheduleRule(weekdays: [foreignWeekday], schedule: .init(startMinute: 540, endMinute: 1020, breakMinutes: 60))
        try model.saveScheduleRules([foreignRule])
        #expect(foreignIncome > 0 && model.expectedIncome(for: model.today) == foreignIncome)
        #expect(model.breakdown.netMonthlyIncome == foreignNet && model.tracking.plan.ratePerSecond > foreignRate)
        try model.saveLeaveDays([foreignDay: LeaveDay(morning: .paid, afternoon: .paid)])
        #expect(model.expectedIncome(for: model.today) == foreignIncome)
        try model.saveLeaveDays([foreignDay: LeaveDay(morning: .unpaid)])
        #expect(abs(model.expectedIncome(for: model.today) - foreignIncome / 2) <= 0.01)
        let parts = foreignDay.split(separator: "-").compactMap { Int($0) }
        let deduction = model.unpaidLeaveDeductions(year: parts[0], monthlyGross: 20_000)
        foreignRule.schedule.endMinute = 1200
        try model.saveScheduleRules([foreignRule])
        #expect(abs(model.expectedIncome(for: model.today) - foreignIncome / 2) <= 0.01)
        #expect(model.unpaidLeaveDeductions(year: parts[0], monthlyGross: 20_000) == deduction)
        model.tracking.shutdown()
    }
}
