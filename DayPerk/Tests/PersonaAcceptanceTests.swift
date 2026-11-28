import Foundation
@testable import DayPerk
import Testing

struct PersonaAcceptanceTests {
    private func policy(_ id: String) throws -> RegionalPayrollPolicy {
        try #require(PayrollCatalog.bundled.policies.first { $0.id == id })
    }
    private func input(_ amount: Double) -> RegionalPayInput {
        var value = RegionalPayInput(); value.amount = amount; value.frequency = .annual; return value
    }
    private func calendar(_ zone: String) -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func sanJoseResidentEngineerHasFederalCaliforniaAndEmployeeDeductions() throws {
        let template = try policy("us-san-jose")
        let value = try InternationalPayrollCalculator().estimate(input: input(150_000), policy: template)
        #expect(template.timeZone == "America/Los_Angeles" && template.currency == "USD")
        #expect(abs(value.annualIncomeTax - 24_734) < 0.01)
        #expect(abs(value.annualRegionalTax - 9_560.86) < 0.01)
        #expect(value.contributions.first { $0.id == "sdi" }?.employee == 1950)
        #expect(abs(value.employeeContributions - 13_425) < 0.01)
        #expect(abs(value.cashNet - 102_280.14) < 0.01)
    }

    @Test func singaporeDomesticWorkerHasNoCPFAndRestDayPayUses26() throws {
        let template = try policy("sg-domestic-worker")
        var worker = input(650 * 12); worker.cpfStatus = "citizen"
        let value = try InternationalPayrollCalculator().estimate(input: worker, policy: template)
        #expect(value.employeeContributions == 0 && value.annualIncomeTax == 0)
        #expect(value.cashNet == 7800)
        let calendar = calendar("Asia/Singapore")
        var plan = WorkPlan(weekdays: [2, 3, 4, 5, 6, 7], overtimeDates: ["2026-11-01": 1, "2026-11-08": 1], referenceSeconds: 8 * 3600)
        plan.registeredDailyGross = 650 / (template.parameters["restDaySalaryDivisor"] ?? 1)
        var day = WorkDayTotal(id: "2026-11-01", seconds: 8 * 3600, overtimeSeconds: 8 * 3600)
        plan.stamp(&day, calendar: calendar)
        #expect(plan.registeredOvertimeGross(for: day, rate: 0) == 25)
        day.seconds = 10 * 3600; day.overtimeSeconds = day.seconds
        #expect(plan.registeredOvertimeGross(for: day, rate: 0) == 25)
        #expect(day.unpaidOvertimeSeconds == 2 * 3600)
        #expect(plan.registeredOvertimeGross(for: WorkDayTotal(id: "2026-11-08", seconds: 4 * 3600), rate: 0) == 25)
        #expect(plan.registeredOvertimeGross(for: day, rate: 0) * 2 == 50)
        #expect(plan.registeredOvertimeGross(for: day, rate: 0) * 4 == 100)
    }

    @Test func seoulSalariedLawyerUsesEmploymentDeductionsAndCaps() throws {
        let value = try InternationalPayrollCalculator().estimate(input: input(100_000_000), policy: policy("kr-seoul"))
        #expect(abs(value.employeeContributions - 8_723_683) < 0.01)
        #expect(abs(value.annualIncomeTax - 11_616_316.08) < 0.01)
        #expect(abs(value.annualRegionalTax - 1_161_631.61) < 0.01)
        #expect(abs(value.cashNet - 78_498_369.31) < 0.01)
    }

    @Test func seoulSolePracticeUsesProfitAndAssessedBillsNotEmployeeDeduction() throws {
        var template = try policy("kr-seoul-self-employed")
        var worker = input(100_000_000)
        #expect(throws: DayPerkInputError.self) { try InternationalPayrollCalculator().estimate(input: worker, policy: template) }
        template.contributions[0].employeeMonthlyAmount = 300_000
        template.contributions[1].employeeMonthlyAmount = 200_000
        worker.declaredContributionsConfirmed = true
        let value = try InternationalPayrollCalculator().estimate(input: worker, policy: template)
        #expect(value.employeeContributions == 6_000_000 && value.employerContributions == 0)
        #expect(value.annualIncomeTax == 16_865_000 && value.annualRegionalTax == 1_686_500)
        #expect(value.cashNet == 75_448_500)
        #expect(!value.contributions.contains { $0.id == "employment" })
    }

    @Test func nagoyaManufacturingLeaderUsesAgeAndPriorYearResidentTax() throws {
        var worker = input(8_000_000)
        worker.age = 45; worker.declaredMonthlySocialBase = 500_000; worker.previousYearGrossIncome = 7_000_000
        let value = try InternationalPayrollCalculator().estimate(input: worker, policy: policy("jp-nagoya"))
        #expect(value.employeeContributions == 942_400)
        #expect(value.annualIncomeTax == 479_700 && value.annualRegionalTax == 387_700)
        #expect(value.cashNet == 6_190_200)
    }

    @Test func nightShiftBoundariesBreaksAndUnpaidTimeUseTheSameDateSpecificSchedule() throws {
        let calendar = calendar("Asia/Tokyo")
        let shift = DayWorkSchedule(startMinute: 22 * 60, endMinute: 7 * 60, breakMode: .timeRanges,
            breaks: [WorkBreak(startMinute: 2 * 60, endMinute: 3 * 60)])
        try shift.validate()
        var rhythm = WorkRhythm(); rhythm.daySchedules = ["2026-11-23": shift]
        let plan = WorkPlan(weekdays: Set(1 ... 7), ratePerSecond: 100 / 3600, dayStartMinute: 12 * 60,
            defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600, rhythm: rhythm)
        #expect(plan.businessDayKey(date(24, 6, calendar: calendar), calendar: calendar) == "2026-11-23")
        #expect(plan.isWithinWorkHours(date(23, 22, 5, calendar: calendar), calendar: calendar))
        #expect(!plan.isWithinWorkHours(date(24, 2, 30, calendar: calendar), calendar: calendar))
        #expect(plan.isWithinWorkHours(date(24, 6, 50, calendar: calendar), calendar: calendar))
        #expect(!plan.isWithinWorkHours(date(24, 7, 35, calendar: calendar), calendar: calendar))
        #expect(plan.isNearRestStart(date(24, 1, 45, calendar: calendar), calendar: calendar))
        #expect(plan.isNearRestEnd(date(24, 2, 55, calendar: calendar), calendar: calendar))
        var day = WorkDayTotal(id: "2026-11-23", seconds: 9 * 3600)
        plan.stamp(&day, calendar: calendar)
        #expect(day.referenceSeconds == 8 * 3600 && day.unpaidOvertimeSeconds == 3600)
        #expect(plan.amount(for: day) == 900)
    }

    @Test func fourOnFourOffAndDatesOnlyWorkWithoutAWeekdayAssumption() throws {
        let calendar = calendar("America/Los_Angeles")
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12))!
        var rhythm = WorkRhythm(enabled: true, anchorDay: "2026-03-05")
        rhythm.cycleDays = [true, true, true, true, false, false, false, false]
        try rhythm.validate()
        for offset in -16 ... 32 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            #expect(rhythm.isWorkday(day, calendar: calendar) == ((offset % 8 + 8) % 8 < 4))
        }
        rhythm.cycleDays = [false]
        var plan = WorkPlan(rhythm: rhythm)
        plan.dateOverrides = ["2026-11-02": true, "2026-11-06": true]
        #expect(plan.regularWorkdays(year: 2026, month: 11, calendar: calendar) == 2)
        plan.rhythm.daySchedules = ["2026-11-02": DayWorkSchedule(startMinute: 600, endMinute: 1020, breakMinutes: 60),
                                   "2026-11-06": DayWorkSchedule(startMinute: 480, endMinute: 1140, breakMinutes: 60)]
        #expect(plan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: calendar) == 16 * 3600)
    }

    @Test func customHoursChangeCurrentValueButDoNotRewriteSettledHours() throws {
        let calendar = calendar("Asia/Shanghai")
        var rhythm = WorkRhythm()
        rhythm.daySchedules = ["2026-11-23": DayWorkSchedule(startMinute: 600, endMinute: 1020, breakMinutes: 60)]
        let plan = WorkPlan(ratePerSecond: 1, defaultDailyExpectedIncome: 800, referenceSeconds: 8 * 3600, rhythm: rhythm)
        var current = WorkDayTotal(id: "2026-11-23", seconds: 7 * 3600)
        plan.stamp(&current, calendar: calendar)
        #expect(current.referenceSeconds == 6 * 3600 && current.unpaidOvertimeSeconds == 3600)
        #expect(plan.expectedIncome(for: current.id, calendar: calendar) == 800)
        var settled = WorkDayTotal(id: "2026-11-23", seconds: 7 * 3600, referenceSeconds: 8 * 3600)
        plan.stamp(&settled, calendar: calendar, preservingExisting: true)
        #expect(settled.referenceSeconds == 8 * 3600 && settled.unpaidOvertimeSeconds == 0)
    }

    @Test func oldConfigurationsDecodeWithoutNewScenarioAndShiftFields() throws {
        let rhythm = try JSONDecoder().decode(WorkRhythm.self, from: Data(#"{"enabled":true,"anchorDay":"2026-01-05","weeks":[[2,3,4,5,6]]}"#.utf8))
        #expect(rhythm.cycleDays == nil && rhythm.daySchedules == nil)
        let original = input(100_000)
        let decoded = try JSONDecoder().decode(RegionalPayInput.self, from: JSONEncoder().encode(original))
        #expect(decoded.declaredContributionsConfirmed == nil && decoded.amount == 100_000)
    }

    @Test func fiveMainlandCityPlansKeepSalaryInputAndProvideUsableDeductions() throws {
        let original = DayPerkConfiguration(baseSalary: 10_000, housingAllowance: 0, workdaysPerMonth: 22,
            startTime: Date.createTime(hour: 9, minute: 0), endTime: Date.createTime(hour: 18, minute: 0),
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday], overtimeMultiplier: 2,
            dateOverrides: [:], currency: .cny, payroll: PayrollDeductionConfiguration(taxMonth: 1, taxYear: 2026), followsCurrentMonth: false)
        #expect(Set(CityPayrollTemplates.all.map(\.id)) == ["beijing", "shanghai", "guangzhou", "shenzhen", "hangzhou"])
        for city in CityPayrollTemplates.all {
            var configured = city.applying(to: original)
            configured.payroll.contributionBase = 10_000; configured.payroll.housingFundBase = 10_000
            try DayPerkModel.validate(configured)
            #expect(configured.baseSalary == 10_000)
            let value = PayrollCalculator.calculate(grossMonthlyIncome: configured.baseSalary, configuration: configured.payroll)
            #expect(value.employeeSocialInsurance > 0 && value.housingFund > 0)
            #expect(value.netMonthlyIncome == PayrollCalculator.money(10_000 - value.employeeSocialInsurance - value.housingFund - value.individualIncomeTax))
        }
    }
}
