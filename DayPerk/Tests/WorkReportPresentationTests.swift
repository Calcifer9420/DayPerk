import AppKit
import Foundation
import Testing
@testable import DayPerk

struct WorkReportPresentationTests {
    @Test func masksOnlyDigitsAndKeepsLocalizedUnitsAndSeparators() {
        let examples = [
            ("¥1,739.39", "¥X,XXX.XX"), ("−999,50 €", "−XXX,XX €"),
            ("USD 114,514.00", "USD XXX,XXX.XX"), ("08:30:30", "XX:XX:XX"),
            ("160:00:00", "XXX:XX:XX"), ("+01:21:15", "+XX:XX:XX"),
            ("1.5 天", "X.X 天"), ("١٢٣٫٤٥ د.إ", "XXX٫XX د.إ"),
        ]
        for (value, masked) in examples {
            #expect(WorkReportPresentation.maskNumbers(value) == masked)
            #expect(WorkReportPresentation.maskNumbers(value).count == value.count)
        }
    }

    @Test func showcaseRevealsOnlyAuthorizedBalancesEvenWhenGlobalAmountsAreHidden() {
        for privacy in [true, false] {
            #expect(WorkReportPresentation.money("¥1,739.39", showcase: true, unlocked: true, privacyEnabled: privacy) == "¥X,XXX.XX")
            #expect(WorkReportPresentation.money("+¥277.56", showcase: true, unlocked: true, privacyEnabled: privacy, isBalance: true) == "+¥277.56")
            #expect(WorkReportPresentation.money("+¥277.56", showcase: true, unlocked: false, privacyEnabled: privacy, isBalance: true) == "+¥XXX.XX")
        }
        #expect(WorkReportPresentation.money("¥1,739.39", showcase: false, unlocked: true, privacyEnabled: false) == "¥1,739.39")
        #expect(WorkReportPresentation.money("¥1,739.39", showcase: false, unlocked: true, privacyEnabled: true) == "•••")
        #expect(WorkReportPresentation.money("¥1,739.39", showcase: false, unlocked: false, privacyEnabled: false) == "•••")
    }

    @Test func showcasePreferenceSurvivesReloadAndIsIncludedInBackups() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-\(UUID())")
        let store = UserDataStore(directory: directory)
        store.set("keep-this-rule", forKey: "dayperkWorkRhythm")
        let privacy = PrivacySettings(defaults: store)
        #expect(!privacy.isStatisticsShowcaseEnabled)
        privacy.isStatisticsShowcaseEnabled = true
        let reloaded = UserDataStore(directory: directory)
        #expect(PrivacySettings(defaults: reloaded).isStatisticsShowcaseEnabled)
        #expect(reloaded.string(forKey: "dayperkWorkRhythm") == "keep-this-rule")
        #expect(AppDataBackup.keys.contains("statisticsShowcaseEnabled"))
    }

    @Test func showcaseKeepsExpectedHoursAndMasksActualHoursAndTimeDifference() {
        #expect(WorkReportPresentation.duration(30_600, showcase: true, expected: true) == "08:30:00")
        #expect(WorkReportPresentation.duration(27_000, showcase: true) == "XX:XX:XX")
        #expect(WorkReportPresentation.duration(-3600, showcase: true, signed: true) == "-XX:XX:XX")
        #expect(WorkReportPresentation.duration(576_000, showcase: true, expected: true) == "160:00:00")
        #expect(WorkReportPresentation.duration(27_000, showcase: false) == "07:30:00")
    }

    @Test func masksHaveTheSameWidthAtTheOriginalFontSizeAndWeight() {
        for size in [13.0, 15.0] {
            for weight in [NSFont.Weight.regular, .semibold] {
                let font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                for value in ["$114,514.00", "08:30:30", "-01:30:30", "160:00:00", "12.345,67 €"] {
                    let original = (value as NSString).size(withAttributes: [.font: font])
                    let masked = (WorkReportPresentation.maskNumbers(value) as NSString).size(withAttributes: [.font: font])
                    #expect(abs(original.width - masked.width) < 0.01)
                    #expect(original.height == masked.height)
                }
            }
        }
    }

    @Test func anUnworkedDaysBalanceCannotExposeTheEntireDailyPay() {
        #expect(!WorkReportPresentation.canShareBalance(expectedIncome: 1739.39, timeValue: 0))
        #expect(WorkReportPresentation.canShareBalance(expectedIncome: 1739.39, timeValue: 1461.83))
        #expect(WorkReportPresentation.canShareBalance(expectedIncome: 0, timeValue: 0))
        #expect(WorkReportPresentation.money("+¥1,739.39", showcase: true, unlocked: true, privacyEnabled: false,
            isBalance: true, balanceIsIncome: true) == "+¥X,XXX.XX")
        let day = WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-23", earned: 0), expectedIncome: 1739.39)
        let worked = WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-24", seconds: 3600, earned: 1000), expectedIncome: 1739.39)
        let report = WorkReport(interval: DateInterval(start: Date(), duration: 86400), days: [day, worked])
        #expect(!WorkReportPresentation.canShareBalance(report))
        #expect(WorkReportPresentation.canShareBalance(WorkReport(interval: report.interval, days: [worked])))
    }

    @Test func lowTimeValueMasksDailyAndAggregateBalancesIncludingTheTenPercentBoundary() {
        for value in [0.0, 0.01, 9.99, 10.0] {
            #expect(!WorkReportPresentation.canShareBalance(expectedIncome: 100, timeValue: value))
            let day = WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-23", earned: value), expectedIncome: 100)
            let worked = WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-24", earned: 80), expectedIncome: 100)
            let report = WorkReport(interval: DateInterval(start: Date(), duration: 172800), days: [day, worked])
            #expect(!WorkReportPresentation.canShareBalance(report))
        }
        #expect(WorkReportPresentation.canShareBalance(expectedIncome: 100, timeValue: 10.01))
        #expect(WorkReportPresentation.canShareBalance(expectedIncome: 0, timeValue: 0))
    }
}
