import SwiftUI

struct WorkRhythmEditor: View {
    @Binding var rhythm: WorkRhythm
    @Binding var weekdays: Set<Weekday>
    var calendar: Calendar
    var allowsHolidayOptOut = false
    var fallback = DayWorkSchedule()
    @State private var editingCycleSlot: String?
    init(rhythm: Binding<WorkRhythm>, weekdays: Binding<Set<Weekday>>, calendar: Calendar, allowsHolidayOptOut: Bool = false, fallback: DayWorkSchedule = DayWorkSchedule(), initiallyEditingCycleSlot: String? = nil) {
        _rhythm = rhythm; _weekdays = weekdays; self.calendar = calendar
        self.allowsHolidayOptOut = allowsHolidayOptOut; self.fallback = fallback
        _editingCycleSlot = State(initialValue: initiallyEditingCycleSlot)
    }
    private var localizedCalendar: Calendar { var c = calendar; c.locale = LocalizationManager.shared.currentLocale; return c }
    private func title(_ key: String) -> Text { Text(L10n.text(key)) }
    private var anchor: Binding<Date> {
        Binding(get: {
            let p = rhythm.anchorDay.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? Date() : Date()
        }, set: { rhythm.anchorDay = WorkPlan.dayKey($0, calendar: calendar) })
    }
    var body: some View {
        HStack {
            title(L10n.text("ui.work_pattern.f6684c77"))
            Spacer()
            Menu {
                Button(L10n.text("ui.monday_to_friday.a16bd7bf")) { rhythm.enabled = false; rhythm.cycleDays = nil; weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday] }
                Button(L10n.text("ui.six_days_sunday_off.6a4f2fe6")) { rhythm.enabled = false; rhythm.cycleDays = nil; weekdays = Set(Weekday.allCases.filter { $0 != .sunday }) }
                Button(L10n.text("ui.alternating_saturdays.8b561d3e")) { rhythm.enabled = true; rhythm.cycleDays = nil; rhythm.weeks = [[2, 3, 4, 5, 6], [2, 3, 4, 5, 6, 7]] }
                Button(L10n.text("schedule.one_on_one_off")) { rhythm.enabled = true; rhythm.cycleDays = [true, false] }
            } label: { title(L10n.text("ui.apply_a_work_pattern.5a915574")) }
        }
        HStack {
            title(L10n.text("ui.repeating_work_cycle.c78a3b2d"))
            InfoHelp(text: L10n.text("ui.choose_a_weekly_cycle_a_day_cycle_o.0eb4c9e2")).frame(width: 18, height: 18)
            Spacer()
            Toggle(L10n.text("ui.repeating_work_cycle.c78a3b2d"), isOn: $rhythm.enabled).labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false))
                .accessibilityLabel(L10n.text("ui.repeating_work_cycle.c78a3b2d"))
        }
        if rhythm.enabled {
            BrewDatePicker(title: L10n.text(rhythm.cycleDays == nil ? "ui.first_cycle_week.e2fadb6d" : "ui.first_cycle_day.17a01630"), selection: anchor, calendar: calendar)
            Picker(selection: Binding(get: { rhythm.cycleDays != nil }, set: { value in
                if value != (rhythm.cycleDays != nil) { rhythm.cycleDays = value ? [true, false] : nil; editingCycleSlot = nil }
            })) {
                title(L10n.text("ui.weeks.cf64435f")).tag(false); title(L10n.text("ui.days.e08c0aa8")).tag(true)
            } label: { title(L10n.text("ui.repeat_by.b63c4b31")) }.pickerStyle(.segmented)
            if let days = rhythm.cycleDays {
                HStack {
                    title("ui.cycle_days.04e5bae5")
                    Spacer()
                    Text(days.count, format: .number).monospacedDigit()
                    Stepper(L10n.text("ui.cycle_days.04e5bae5"), value: Binding(get: { rhythm.cycleDays?.count ?? 1 }, set: { count in
                        editingCycleSlot = nil
                        if count > days.count { rhythm.cycleDays = days + Array(repeating: false, count: count - days.count) }
                        else { rhythm.cycleDays = Array(days.prefix(count)) }
                    }), in: 1 ... 56).labelsHidden().fixedSize()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                    ForEach(days.indices, id: \.self) { index in
                        VStack(spacing: 6) {
                            Toggle(isOn: Binding(get: { rhythm.cycleDays?[index] ?? false }, set: { rhythm.cycleDays?[index] = $0 })) {
                                Text(L10n.format("cycle.day", String(index + 1)))
                            }.toggleStyle(BrewToggleStyle(checkbox: true))
                            cycleTimeButton(slot: WorkRhythm.daySlot(index), enabled: days[index])
                        }.padding(.vertical, 4)
                    }
                }
            } else {
            HStack {
                title("ui.cycle_weeks.a9810ab9")
                Spacer()
                Text(rhythm.weeks.count, format: .number).monospacedDigit()
                Stepper(L10n.text("ui.cycle_weeks.a9810ab9"), value: Binding(get: { rhythm.weeks.count }, set: { count in
                    editingCycleSlot = nil
                    if count > rhythm.weeks.count { rhythm.weeks += Array(repeating: Set([2, 3, 4, 5, 6]), count: count - rhythm.weeks.count) }
                    else { rhythm.weeks = Array(rhythm.weeks.prefix(count)) }
                }), in: 1 ... 8).labelsHidden().fixedSize()
            }
            ForEach(rhythm.weeks.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text(L10n.format("cycle.week", String(index + 1))).frame(width: 60, alignment: .leading)
                    ForEach(0 ..< 7) { offset in
                        let day = (offset + 1) % 7 + 1
                        VStack(spacing: 6) {
                            Toggle(isOn: Binding(get: { rhythm.weeks[index].contains(day) }, set: {
                                if $0 { rhythm.weeks[index].insert(day) } else { rhythm.weeks[index].remove(day) }
                            })) { Text(localizedCalendar.shortStandaloneWeekdaySymbols[day - 1]) }
                                .toggleStyle(BrewToggleStyle(checkbox: true))
                            cycleTimeButton(slot: WorkRhythm.weekSlot(index, weekday: day), enabled: rhythm.weeks[index].contains(day))
                        }.frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                }
            }
            }
            if let slot = editingCycleSlot, rhythm.cycleSchedules?[slot] != nil {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(cycleSlotTitle(slot)).fontWeight(.semibold)
                        Spacer()
                        Button(L10n.text("schedule.use_default")) {
                            rhythm.cycleSchedules?[slot] = nil; editingCycleSlot = nil
                            ActionToastCenter.shared.show(L10n.text("schedule.default_restored"))
                        }
                    }
                    DayWorkScheduleFields(schedule: Binding(get: { rhythm.cycleSchedules?[slot] ?? fallback }, set: { rhythm.cycleSchedules?[slot] = $0 }), calendar: calendar)
                }.padding(14).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        } else {
            HStack(spacing: 10) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Toggle(isOn: Binding(get: { weekdays.contains(day) }, set: {
                        if $0 { weekdays.insert(day) } else { weekdays.remove(day) }
                    })) { Text(localizedCalendar.shortStandaloneWeekdaySymbols[day.calendarWeekday - 1]) }
                        .toggleStyle(BrewToggleStyle(checkbox: true))
                }
            }
        }
        if allowsHolidayOptOut {
            HStack {
                title(L10n.text("ui.apply_public_holidays_to_my_schedul.9a174ea4"))
                InfoHelp(text: L10n.text("ui.turn_this_off_when_public_holidays.d5bb0ccd")).frame(width: 18, height: 18)
                Spacer()
                Toggle(L10n.text("ui.apply_public_holidays_to_my_schedul.9a174ea4"), isOn: Binding(get: { rhythm.observesPublicHolidays ?? true }, set: { rhythm.observesPublicHolidays = $0 })).labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false))
                    .accessibilityLabel(L10n.text("ui.apply_public_holidays_to_my_schedul.9a174ea4"))
            }
        }
    }

    private func cycleTimeButton(slot: String, enabled: Bool) -> some View {
        let custom = rhythm.cycleSchedules?[slot]
        return Button {
            if custom == nil {
                var items = rhythm.cycleSchedules ?? [:]; items[slot] = fallback; rhythm.cycleSchedules = items
            }
            editingCycleSlot = slot
        } label: {
            Text(custom.map(\.timeSummary) ?? L10n.text("schedule.default_hours"))
                .font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(custom == nil ? Color.secondary : AppearanceSettings.shared.theme.color)
                .frame(maxWidth: .infinity, minHeight: 20)
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
            .accessibilityLabel(cycleSlotTitle(slot) + ": " + L10n.text("schedule.edit_hours"))
    }

    private func cycleSlotTitle(_ slot: String) -> String {
        let parts = slot.split(separator: ":")
        if parts.count == 2, let day = Int(parts[1]) { return L10n.format("cycle.day", String(day + 1)) }
        if parts.count == 3, let week = Int(parts[1]), let weekday = Int(parts[2]) {
            return L10n.format("cycle.week", String(week + 1)) + " · " + localizedCalendar.standaloneWeekdaySymbols[weekday - 1]
        }
        return L10n.text("schedule.edit_hours")
    }
}

struct DayScheduleEditor: View {
    @Binding var rhythm: WorkRhythm
    var day: String
    var fallback: DayWorkSchedule
    var calendar: Calendar
    private var schedule: Binding<DayWorkSchedule> {
        Binding(get: { rhythm.daySchedules?[day] ?? fallback }, set: { value in
            var items = rhythm.daySchedules ?? [:]; items[day] = value; rhythm.daySchedules = items
        })
    }
    var body: some View {
        HStack {
            Text(L10n.text("ui.custom_hours_for_selected_date.4fe69103"))
            InfoHelp(text: L10n.text("ui.set_that_date_s_shift_and_breaks_in.da911e7e")).frame(width: 18, height: 18)
            Spacer()
            Toggle(L10n.text("ui.custom_hours_for_selected_date.4fe69103"), isOn: Binding(get: { rhythm.daySchedules?[day] != nil }, set: { enabled in
                let inherited = rhythm.schedule(for: day, fallback: fallback)
                var items = rhythm.daySchedules ?? [:]; items[day] = enabled ? inherited : nil; rhythm.daySchedules = items
            })).labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false))
                .accessibilityLabel(L10n.text("ui.custom_hours_for_selected_date.4fe69103"))
        }
        if rhythm.daySchedules?[day] != nil {
            DayWorkScheduleFields(schedule: schedule, calendar: calendar)
        }
    }
}

/// 日期、循环和规则共用一套时间编辑，休息时段与跨午夜校验保持一致。
struct DayWorkScheduleFields: View {
    @Binding var schedule: DayWorkSchedule
    var calendar: Calendar
    private func time(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { calendar.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                set: { value.wrappedValue = calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) })
    }
    var body: some View {
            ScheduleTimeRange(startTitle: "ui.shift_starts.a9a90d2f", endTitle: "ui.shift_ends.03ef2368", start: time($schedule.startMinute), end: time($schedule.endMinute))
            Picker(L10n.text("ui.break_mode.0cbad458"), selection: $schedule.breakMode) {
                ForEach(WorkBreakMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented)
            if schedule.breakMode == .totalHours {
                LabeledContent(L10n.text("ui.daily_reference_break.8e206a2b")) {
                    TextField("", value: Binding(get: { Double(schedule.breakMinutes) / 60 }, set: {
                        if $0.isFinite && (0 ... 24).contains($0) { schedule.breakMinutes = Int(($0 * 60).rounded()) }
                    }), format: .number.precision(.fractionLength(0 ... 2)))
                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 100)
                    Text(L10n.text("ui.hours.3b6fefc5"))
                }
            } else {
                HStack {
                    Text(L10n.text("ui.exclude_break_periods.570bd524"))
                    Spacer()
                    Button(L10n.text("ui.add_break_period.02ecdb1d"), systemImage: "plus") {
                        schedule.breaks.append(WorkBreak(startMinute: schedule.startMinute, endMinute: (schedule.startMinute + 30) % 1440))
                    }.labelStyle(.iconOnly).help(L10n.text("ui.add_break_period.02ecdb1d"))
                }
                ForEach($schedule.breaks) { $period in
                    HStack {
                        ScheduleTimeRange(startTitle: "ui.break_starts.65d83a76", endTitle: "ui.break_ends.91dcd170", start: time($period.startMinute), end: time($period.endMinute))
                        Button(L10n.text("ui.remove.c3812fc4"), systemImage: "trash", role: .destructive) { schedule.breaks.removeAll { $0.id == period.id } }
                            .labelStyle(.iconOnly).help(L10n.text("ui.remove.c3812fc4"))
                    }
                }
            }
            LabeledContent(L10n.text("ui.daily_reference_hours.c7992324"), value: (Double(schedule.referenceMinutes) / 60).formatted(.number.locale(LocalizationManager.shared.currentLocale)) + " " + L10n.text("ui.hours.3b6fefc5"))
    }
}

/// 标签紧跟各自的时间，避免表单把开始时间挤到结束标签旁边。
struct ScheduleTimeRange: View {
    var startTitle: String
    var endTitle: String
    @Binding var start: Date
    @Binding var end: Date
    var body: some View {
        HStack(spacing: 28) {
            HStack(spacing: 8) {
                Text(L10n.text(startTitle))
                DatePicker(L10n.text(startTitle), selection: $start, displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            HStack(spacing: 8) {
                Text(L10n.text(endTitle))
                DatePicker(L10n.text(endTitle), selection: $end, displayedComponents: .hourAndMinute)
                    .labelsHidden().fixedSize()
            }
            Spacer(minLength: 0)
        }.datePickerStyle(.field)
    }
}
