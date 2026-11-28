import SwiftUI

struct WorkDataCorrectionView: View {
    @ObservedObject var model: DayPerkModel
    @State private var selectedDate: Date
    @State private var endDate: Date
    @State private var range = false
    @State private var time = ""
    @State private var shift = DayWorkSchedule()
    @State private var useRule = false
    @State private var ruleID: UUID?

    init(model: DayPerkModel) {
        self.model = model
        let day = model.tracking.plan.businessDayStart(for: Date(), calendar: model.workCalendar)
        _selectedDate = State(initialValue: day); _endDate = State(initialValue: day)
    }
    private var key: String { WorkPlan.dayKey(selectedDate, calendar: model.workCalendar) }
    private var today: Date { model.tracking.plan.businessDayStart(for: Date(), calendar: model.workCalendar) }
    private var record: WorkDayTotal { model.tracking.state.days.first { $0.id == key } ?? WorkDayTotal(id: key) }
    private var matchingRules: [WorkScheduleRule] { (model.rhythm.scheduleRules ?? []).filter { !matches($0).isEmpty } }
    private var selectedRule: WorkScheduleRule? { matchingRules.first { $0.id == ruleID } ?? matchingRules.first }
    private func matches(_ rule: WorkScheduleRule? = nil) -> [String] {
        (try? WorkDataCorrection.dates(from: selectedDate, through: range ? endDate : selectedDate,
            asOf: today, plan: model.businessPlan, calendar: model.workCalendar, rule: rule)) ?? []
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text("correction.choose_date"))
                    Spacer()
                    Toggle(L10n.text("correction.date_range"), isOn: $range).fixedSize()
                }
                HolidayCalendarView(overrides: .constant(model.effectiveOverrides), selectedDate: $selectedDate,
                    overtimeDates: model.overtimeDates, region: model.regional.region, subdivision: model.regional.selectedPolicy.subdivision,
                    rhythm: model.rhythm, weekdays: model.businessPlan.weekdays, workCalendar: model.workCalendar, leaveDays: model.leaveDays,
                    selectionEnd: range ? $endDate : nil,
                    selectionBounds: (model.workCalendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast) ... today,
                    showsRefreshButton: false)
            }
            if !range { actualSection }
            scheduleSection
        }.formStyle(.grouped).onAppear(perform: load)
            .onChange(of: selectedDate) { _, _ in if !range { endDate = selectedDate }; load() }
            .onChange(of: range) { _, _ in endDate = selectedDate }
    }

    private var actualSection: some View {
        let seconds = (try? WorkDurationInput.parse(time)) ?? 0
        let expectedSeconds = model.expectedWorkSeconds(for: record)
        let preview = model.previewWorkCorrection(key, seconds: seconds)
        return Section(L10n.text("correction.actual_hours")) {
            HStack {
                Text(L10n.text("ui.tracked_time_hh_mm_ss.9fa0699c"))
                Spacer()
                TextField("00:00:00", text: $time).labelsHidden().multilineTextAlignment(.trailing)
                    .monospacedDigit().textFieldStyle(.roundedBorder).frame(width: 150)
                    .accessibilityLabel(L10n.text("ui.tracked_time_hh_mm_ss.9fa0699c"))
            }
            LabeledContent(L10n.text("report.expected_work_time"), value: WorkDurationInput.format(expectedSeconds)).monospacedDigit()
            LabeledContent(L10n.text("report.time_difference")) {
                Text(WorkDurationInput.formatSeconds(Int((seconds - expectedSeconds).rounded()), signed: true)).monospacedDigit()
                    .foregroundStyle(WorkBalancePresentation.timeColor(for: Int(seconds - expectedSeconds)))
            }
            LabeledContent(L10n.text("ui.recalculated_time_value.8cd7163d"), value: model.access.settingsUnlocked && !model.privacy.isPrivacyModeEnabled ? model.currency.formatAmount(preview.earned, currencyCode: preview.currencyCode) : "•••")
            HStack {
                Button(L10n.text("ui.clear_inputs.3d661180")) {
                    time = "00:00:00"
                    ActionToastCenter.shared.show(L10n.text("correction.input_cleared"))
                }
                Spacer()
                Button(L10n.text("correction.reload_actual"), systemImage: "arrow.counterclockwise") {
                    time = WorkDurationInput.format(record.seconds)
                    ActionToastCenter.shared.show(L10n.text("correction.actual_reloaded"))
                }.labelStyle(.iconOnly).help(L10n.text("correction.reload_actual"))
                Button(L10n.text("correction.save_actual"), systemImage: "checkmark", action: saveActual)
                    .labelStyle(.iconOnly).help(L10n.text("correction.save_actual")).buttonStyle(BrewButtonStyle(prominent: true))
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker(L10n.text("correction.method"), selection: $useRule) {
                Text(L10n.text("correction.manual_schedule")).tag(false)
                Text(L10n.text("correction.use_rule")).tag(true)
            }.pickerStyle(.segmented)
            if useRule {
                if let selectedRule {
                    Picker(L10n.text("correction.select_rule"), selection: Binding(get: { self.selectedRule?.id ?? selectedRule.id }, set: { ruleID = $0 })) {
                        ForEach(matchingRules) { rule in
                            let index = (model.rhythm.scheduleRules ?? []).firstIndex { $0.id == rule.id } ?? 0
                            Text(rule.name.isEmpty ? L10n.format("schedule.rule_number", String(index + 1)) : rule.name).tag(rule.id)
                        }
                    }
                    Text(selectedRule.schedule.timeSummary).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    LabeledContent(L10n.text("correction.select_rule"), value: L10n.text("correction.no_matching_rules"))
                }
                if model.rhythm.scheduleRules?.isEmpty != false { Text(L10n.text("correction.rules_hint")).foregroundStyle(.secondary) }
            } else {
                DayWorkScheduleFields(schedule: $shift, calendar: model.workCalendar)
            }
            HStack {
                Text(L10n.format("correction.match_count", String(useRule ? selectedRule.map { matches($0).count } ?? 0 : matches().count))).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("correction.save_schedule"), systemImage: "checkmark", action: saveSchedule)
                    .labelStyle(.iconOnly).help(L10n.text("correction.save_schedule")).buttonStyle(BrewButtonStyle(prominent: true))
                    .disabled(useRule ? selectedRule.map { matches($0).isEmpty } ?? true : matches().isEmpty)
            }
        } header: {
            HStack(spacing: 8) {
                Text(L10n.text("correction.expected_schedule"))
                InfoHelp(text: L10n.text("correction.schedule_help")).frame(width: 18, height: 18)
            }
        }
    }
    private func load() {
        time = WorkDurationInput.format(record.seconds)
        shift = model.rhythm.schedule(for: key, fallback: model.configuration.referenceSchedule)
        if ruleID == nil { ruleID = model.rhythm.scheduleRules?.first { $0.matches(key) }?.id }
    }
    private func saveActual() {
        do {
            try model.correctWorkTime(key, seconds: WorkDurationInput.parse(time))
            load()
            ActionToastCenter.shared.show(L10n.text("correction.actual_saved"))
        } catch { ActionToastCenter.shared.show(error.localizedDescription, isError: true) }
    }
    private func saveSchedule() {
        do {
            let count = try model.correctWorkSchedules(from: selectedDate, through: range ? endDate : selectedDate,
                schedule: useRule ? nil : shift, ruleID: useRule ? selectedRule?.id : nil)
            load(); ActionToastCenter.shared.show(L10n.format("correction.schedule_saved", String(count)))
        } catch { ActionToastCenter.shared.show(error.localizedDescription, isError: true) }
    }
}
