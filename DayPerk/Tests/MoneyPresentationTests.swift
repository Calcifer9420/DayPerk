import Foundation
import SwiftUI
import Testing
@testable import DayPerk

struct MoneyPresentationTests {
    @Test func subCentBalancesAreNeutralAndDoNotCarryASign() {
        for value in [-0.0017017543864312756, -0.00000000001, -0.0, 0.0, 0.00001, 0.0049] {
            let shown = MoneyDisplaySettings.normalizedForDisplay(value, decimalPlaces: 2)
            #expect(shown == 0 && shown.sign == .plus)
            #expect(WorkBalancePresentation.color(for: value, visible: true) == .secondary)
        }
        #expect(WorkBalancePresentation.timeColor(for: 0) == .secondary)
        #expect(WorkBalancePresentation.color(for: -0.0051, visible: true) == .red)
        #expect(WorkBalancePresentation.color(for: 0.0051, visible: true) == .green)
    }

    @Test func zeroUsesTheSelectedPrecisionAndTheFormattersHalfEvenRule() {
        for places in 0...2 {
            let halfUnit = 0.5 / pow(10, Double(places))
            for value in [-halfUnit, halfUnit] {
                #expect(MoneyDisplaySettings.normalizedForDisplay(value, decimalPlaces: places) == 0)
                #expect(WorkBalancePresentation.color(for: value, visible: true, decimalPlaces: places) == .secondary)
            }
            #expect(WorkBalancePresentation.color(for: -halfUnit * 1.01, visible: true, decimalPlaces: places) == .red)
            #expect(WorkBalancePresentation.color(for: halfUnit * 1.01, visible: true, decimalPlaces: places) == .green)
        }
    }

    @Test func displayNormalizationDoesNotRoundTheReportOrLoseSubCentTotals() {
        let days = [WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-23", earned: 0), expectedIncome: 0.004),
                    WorkReportDay(date: Date(), total: WorkDayTotal(id: "2026-11-24", earned: 0), expectedIncome: 0.004)]
        let report = WorkReport(interval: DateInterval(start: Date(), duration: 86400), days: days)
        #expect(days.allSatisfy { MoneyDisplaySettings.normalizedForDisplay($0.balance, decimalPlaces: 2) == 0 })
        #expect(report.balance == 0.008)
        #expect(MoneyDisplaySettings.normalizedForDisplay(report.balance, decimalPlaces: 2) == 0.008)
        #expect(WorkBalancePresentation.color(for: report.balance, visible: true) == .green)
    }
}
