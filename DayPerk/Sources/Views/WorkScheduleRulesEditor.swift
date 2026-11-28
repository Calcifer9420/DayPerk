import AppKit
import SwiftUI

/// 规则按列表顺序匹配，编辑始终留在工作安排页面的待保存配置里。
struct WorkScheduleRulesEditor: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Binding var rhythm: WorkRhythm
    var fallback: DayWorkSchedule
    var calendar: Calendar
    @State private var expandedID: UUID?
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @GestureState private var draggingHandle = false

    init(rhythm: Binding<WorkRhythm>, fallback: DayWorkSchedule, calendar: Calendar, initiallyExpandedRuleID: UUID? = nil) {
        _rhythm = rhythm; self.fallback = fallback; self.calendar = calendar
        _expandedID = State(initialValue: initiallyExpandedRuleID)
    }

    private var rules: [WorkScheduleRule] { rhythm.scheduleRules ?? [] }
    private var dragLayout: DragReorderLayout? {
        guard let source = rules.firstIndex(where: { $0.id == draggingID }) else { return nil }
        return DragReorderLayout(source: source, translation: dragTranslation, heights: rules.map { rowHeights[$0.id] ?? 0 })
    }
    private var localizedCalendar: Calendar {
        var value = calendar; value.locale = LocalizationManager.shared.currentLocale; return value
    }

    var body: some View {
        Section {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                ruleCard(rule, index: index)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[rule.id] = $0 }
                    .offset(y: dragLayout?.offset(at: index) ?? 0)
                    .zIndex(draggingID == rule.id ? 1 : 0)
                    .animation(draggingID == rule.id ? nil : .easeInOut(duration: 0.16), value: dragLayout?.target)
            }
        }.onChange(of: draggingHandle) { _, active in
            if !active, draggingID != nil { cancelDrag() }
        }
        } header: {
            HStack(spacing: 6) {
                Text(L10n.text("schedule.special_rules"))
                InfoHelp(text: L10n.text("schedule.rules_order") + "\n\n" + L10n.text("schedule.priority_help")).frame(width: 18, height: 18)
                Spacer()
                Button(L10n.text("schedule.add_rule"), systemImage: "plus") {
                    let day = WorkPlan.dayKey(Date(), calendar: calendar)
                    let rule = WorkScheduleRule(anchorDay: day, effectiveFromDay: day, schedule: fallback)
                    rhythm.scheduleRules = rules + [rule]; expandedID = rule.id
                    ActionToastCenter.shared.show(L10n.text("schedule.rule_added"))
                }.labelStyle(.iconOnly).help(L10n.text("schedule.add_rule")).buttonStyle(BrewButtonStyle())
            }
        }
    }

    private func binding(_ rule: WorkScheduleRule) -> Binding<WorkScheduleRule> {
        Binding(get: { rules.first { $0.id == rule.id } ?? rule }, set: { value in
            if let index = rhythm.scheduleRules?.firstIndex(where: { $0.id == rule.id }) { rhythm.scheduleRules?[index] = value }
        })
    }

    private func ruleCard(_ rule: WorkScheduleRule, index: Int) -> some View {
        let value = binding(rule)
        let title = rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.format("schedule.rule_number", String(index + 1)) : rule.name
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    expandedID = expandedID == rule.id ? nil : rule.id
                } label: {
                    HStack(spacing: 6) {
                        Text(title).fontWeight(.semibold).lineLimit(1)
                        Image(systemName: expandedID == rule.id ? "chevron.down" : "chevron.right")
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.text("ui.remove.c3812fc4"), systemImage: "trash", role: .destructive) {
                    rhythm.scheduleRules?.removeAll { $0.id == rule.id }
                    rowHeights[rule.id] = nil
                    if expandedID == rule.id { expandedID = nil }
                    ActionToastCenter.shared.show(L10n.text("schedule.rule_removed"))
                }.labelStyle(.iconOnly).help(L10n.text("ui.remove.c3812fc4"))
                Button {} label: { Image(systemName: "line.3.horizontal").frame(width: 16, height: 16) }
                    .buttonStyle(BrewButtonStyle())
                    .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .updating($draggingHandle) { _, active, _ in active = true }
                        .onChanged { value in
                            if draggingID == nil { draggingID = rule.id }
                            dragTranslation = value.translation.height
                            NSCursor.closedHand.set()
                        }
                        .onEnded { value in
                            dragTranslation = value.translation.height
                            finishDrag()
                            NSCursor.openHand.set()
                        })
                    .onHover { inside in
                        if draggingID == nil { (inside ? NSCursor.openHand : .arrow).set() }
                    }
                    .help(L10n.text("schedule.drag_reorder"))
                    .accessibilityElement().accessibilityLabel(L10n.text("schedule.drag_reorder") + ": " + title)
                    .accessibilityAction(named: Text(L10n.text("schedule.move_up"))) { move(rule, by: -1) }
                    .accessibilityAction(named: Text(L10n.text("schedule.move_down"))) { move(rule, by: 1) }
                Toggle(title, isOn: value.enabled).labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false)).accessibilityLabel(title)
            }
            Text(summary(rule)).font(.callout).foregroundStyle(.secondary)
            if expandedID == rule.id {
                Divider()
                HStack(spacing: 12) {
                    Text(L10n.text("schedule.rule_name"))
                    TextField("", text: value.name, prompt: Text(L10n.text("schedule.rule_name_optional")))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("schedule.rule_name"))
                }
                HStack(spacing: 10) {
                    ForEach(0 ..< 7) { offset in
                        let day = (offset + 1) % 7 + 1
                        Toggle(isOn: Binding(get: { value.wrappedValue.weekdays.contains(day) }, set: { selected in
                            if selected { value.wrappedValue.weekdays.insert(day) } else { value.wrappedValue.weekdays.remove(day) }
                        })) { Text(localizedCalendar.shortStandaloneWeekdaySymbols[day - 1]) }
                            .toggleStyle(BrewToggleStyle(checkbox: true))
                    }
                }
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Text(recurrence(rule))
                        Stepper(L10n.text("schedule.repeating_weeks"), value: value.intervalWeeks, in: 1 ... 52).labelsHidden().fixedSize()
                    }.fixedSize()
                    if rule.intervalWeeks > 1 {
                        HStack(spacing: 6) {
                            Text(L10n.text("schedule.first_matching_week"))
                            BrewDatePicker(title: L10n.text("schedule.first_matching_week"), selection: anchor(value), calendar: calendar, showsLabel: false).fixedSize()
                        }.fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                DayWorkScheduleFields(schedule: value.schedule, calendar: calendar)
            }
        }.padding(14)
            .background(draggingID == rule.id ? appearance.theme.surface : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(appearance.theme.color.opacity(draggingID == rule.id ? 0.9 : 0), lineWidth: 2))
            .shadow(color: .black.opacity(draggingID == rule.id ? 0.24 : 0), radius: 8, y: 4)
    }

    private func finishDrag() {
        guard let id = draggingID, let layout = dragLayout else { cancelDrag(); return }
        let target = rules[layout.target].id
        withAnimation(.easeInOut(duration: 0.18)) {
            let moved = rhythm.moveScheduleRule(id, to: target)
            draggingID = nil; dragTranslation = 0
            if moved { ActionToastCenter.shared.show(L10n.text("schedule.rule_reordered")) }
        }
    }

    private func cancelDrag() {
        withAnimation(.easeInOut(duration: 0.18)) { draggingID = nil; dragTranslation = 0 }
        NSCursor.arrow.set()
    }

    private func anchor(_ value: Binding<WorkScheduleRule>) -> Binding<Date> {
        Binding(get: {
            let parts = value.wrappedValue.anchorDay.split(separator: "-").compactMap { Int($0) }
            return parts.count == 3 ? calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date() : Date()
        }, set: { value.wrappedValue.anchorDay = WorkPlan.dayKey($0, calendar: calendar) })
    }

    private func recurrence(_ rule: WorkScheduleRule) -> String {
        rule.intervalWeeks == 1 ? L10n.text("schedule.every_week") : L10n.format("schedule.every_n_weeks", String(rule.intervalWeeks))
    }

    private func summary(_ rule: WorkScheduleRule) -> String {
        let days = (0 ..< 7).map { ($0 + 1) % 7 + 1 }.filter { rule.weekdays.contains($0) }
            .map { localizedCalendar.shortStandaloneWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        return [recurrence(rule), days, rule.schedule.timeSummary].joined(separator: " · ")
    }

    private func move(_ rule: WorkScheduleRule, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }), rules.indices.contains(index + offset) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { rhythm.moveScheduleRule(rule.id, to: rules[index + offset].id) }
        ActionToastCenter.shared.show(L10n.text("schedule.rule_reordered"))
    }
}
