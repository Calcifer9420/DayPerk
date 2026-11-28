import SwiftUI

/// 共用日历下的休假编辑区，普通休假和调休复用整段与分段配置。
struct LeaveEditorSections: View {
    @ObservedObject var model: DayPerkModel
    @Binding var draft: LeaveRequestDraft
    @State private var message = ""
    @State private var isError = false

    private var requests: [LeaveRequest] { model.leaveRequests }
    private var baseBounds: ClosedRange<Date> { min(draft.base.start, draft.base.end) ... max(draft.base.start, draft.base.end) }

    var body: some View {
        Group {
            if draft.isSelecting {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        if draft.confirmedBase != nil {
                            HStack {
                                Text(L10n.text("leave.continuous")).font(.headline)
                                if draft.selectedSegmentID != nil {
                                    Label(L10n.text("leave.saved_period"), systemImage: "checkmark.circle.fill")
                                        .font(.subheadline).foregroundStyle(.green)
                                }
                                Spacer()
                                Button(role: .destructive) { removeRequest(draft.id) } label: { Image(systemName: "trash") }
                                    .accessibilityLabel(L10n.text("leave.remove_period")).help(L10n.text("leave.remove_period"))
                            }
                        }
                        if draft.selectedSegmentID == nil {
                            rangeEditor($draft.base)
                            dayCount(draft.request)
                        } else {
                            requestSummary(draft.request)
                        }
                        LeaveRequestTimeline(request: draft.request, selectedSegmentID: draft.selectedSegmentID, calendar: model.workCalendar)
                        ForEach($draft.changes) { $range in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(L10n.format("leave.change_title", String((draft.changes.firstIndex { $0.id == range.id } ?? 0) + 1))).font(.subheadline.weight(.medium))
                                    Spacer()
                                    if draft.selectedSegmentID != range.id {
                                        Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") { selectSegment(range.id) }
                                            .labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656"))
                                    } else {
                                        Button(L10n.text("leave.save_segment"), systemImage: "checkmark") { save(finish: false) }
                                            .labelStyle(.iconOnly).help(L10n.text("leave.save_segment"))
                                            .buttonStyle(BrewButtonStyle(prominent: true))
                                    }
                                    Button(role: .destructive) { removeDraftSegment(range.id) } label: { Image(systemName: "trash") }
                                        .accessibilityLabel(L10n.text("leave.remove_range")).help(L10n.text("leave.remove_range"))
                                }
                                if draft.selectedSegmentID == range.id {
                                    rangeEditor($range, bounds: baseBounds)
                                } else { summary(range) }
                            }.padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        HStack {
                            Spacer()
                            if draft.selectedSegmentID == nil {
                                Button(L10n.text("leave.save"), systemImage: "checkmark") { save(finish: true) }
                                    .labelStyle(.iconOnly).help(L10n.text("leave.save"))
                                    .buttonStyle(BrewButtonStyle(prominent: true))
                            }
                        }
                    }.transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["leave-range"] = anchor }
                } header: {
                    HStack {
                        Text(L10n.text("leave.continuous"))
                        InfoHelp(text: L10n.text("leave.range_help")).frame(width: 18, height: 18)
                        Spacer()
                        Button(L10n.text(draft.changes.isEmpty ? "leave.adjust_segment" : "leave.add_next_segment"), systemImage: "plus", action: addSegment)
                            .labelStyle(.iconOnly).help(L10n.text(draft.changes.isEmpty ? "leave.adjust_segment" : "leave.add_next_segment"))
                    }
                }
            }
            if requests.contains(where: { !draft.isSelecting || $0.id != draft.id }) {
                Section(L10n.text("leave.saved")) {
                    ForEach(requests.filter { !draft.isSelecting || $0.id != draft.id }) { request in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                requestSummary(request)
                                Spacer()
                                Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") { draft.edit(request) }
                                    .labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656"))
                                Button(role: .destructive) { removeRequest(request.id) } label: { Image(systemName: "trash") }
                                    .accessibilityLabel(L10n.text("leave.remove_period")).help(L10n.text("leave.remove_period"))
                            }
                            LeaveRequestTimeline(request: request, calendar: model.workCalendar)
                            ForEach(Array(request.segments.enumerated()), id: \.element.id) { index, segment in
                                HStack(spacing: 10) {
                                    Text(L10n.format("leave.change_title", String(index + 1))).foregroundStyle(.secondary)
                                    summary(segment)
                                    Spacer()
                                    Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") { draft.edit(request, segmentID: segment.id) }
                                        .labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656"))
                                    Button(role: .destructive) { removeSavedSegment(segment.id, from: request) } label: { Image(systemName: "trash") }
                                        .accessibilityLabel(L10n.text("leave.remove_range")).help(L10n.text("leave.remove_range"))
                                }.padding(.leading, 16)
                            }
                        }.padding(.vertical, 8)
                    }
                }
            }
        }.actionFeedback($message, isError: isError)
    }

    private func summary(_ range: LeaveRange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LeaveRequestTimeline.label(range, calendar: model.workCalendar)).monospacedDigit()
            Text(range.summary).foregroundStyle(.secondary)
        }
    }
    private func dayCount(_ request: LeaveRequest) -> some View {
        Group {
            if let text = dayCountText(request) {
                Text(text)
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func requestSummary(_ request: LeaveRequest) -> some View {
        if let count = dayCountText(request) {
            Text(L10n.format("leave.period_overview", LeaveRequestTimeline.label(request.base, calendar: model.workCalendar),
                request.base.summary, count))
                .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        } else {
            summary(request.base)
        }
    }
    private func dayCountText(_ request: LeaveRequest) -> String? {
        guard let total = try? LeaveRequests.summary(request, plan: model.businessPlan, calendar: model.workCalendar) else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.locale(LocalizationManager.shared.currentLocale).precision(.fractionLength(0 ... 1))
        return L10n.format("leave.actual_days", (total.paidDays + total.unpaidDays).formatted(format),
            total.paidDays.formatted(format), total.unpaidDays.formatted(format))
    }
    private func addSegment() {
        do {
            try model.saveLeaveRequest(&draft, addSegment: true)
            message = L10n.text("leave.saved_next_segment"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
    private func selectSegment(_ id: UUID) {
        do {
            try model.saveLeaveRequest(&draft)
            draft.selectedSegmentID = id
        } catch { message = error.localizedDescription; isError = true }
    }
    private func removeDraftSegment(_ id: UUID) {
        var next = draft; next.changes.removeAll { $0.id == id }
        if next.selectedSegmentID == id { next.selectedSegmentID = nil }
        do {
            try model.saveLeaveRequest(&next); draft = next
            message = L10n.text("leave.removed_segment"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
    private func removeSavedSegment(_ id: UUID, from request: LeaveRequest) {
        var next = request; next.segments.removeAll { $0.id == id }
        do {
            try model.saveLeaveRequests(requests.map { $0.id == next.id ? next : $0 })
            message = L10n.text("leave.removed_segment"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }
    private func removeRequest(_ id: UUID) {
        do {
            try model.saveLeaveRequests(requests.filter { $0.id != id })
            if draft.id == id { draft.isSelecting = false }
            message = L10n.text("leave.removed_feedback"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }

    private func rangeEditor(_ range: Binding<LeaveRange>, bounds: ClosedRange<Date> = Date.distantPast ... Date.distantFuture) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                HStack(spacing: 8) {
                    Text(L10n.text("leave.from"))
                    BrewDatePicker(title: L10n.text("leave.from"), selection: range.start, calendar: model.workCalendar, bounds: bounds, showsLabel: false).fixedSize()
                }
                HStack(spacing: 8) {
                    Text(L10n.text("leave.through"))
                    BrewDatePicker(title: L10n.text("leave.through"), selection: range.end, calendar: model.workCalendar, bounds: bounds, showsLabel: false).fixedSize()
                }
                Spacer(minLength: 0)
            }.datePickerStyle(.field)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { portionPicker(range); payPicker(range); kindPicker(range); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 12) {
                    portionPicker(range)
                    HStack(spacing: 16) { payPicker(range); kindPicker(range); Spacer(minLength: 0) }
                }
            }
            if range.wrappedValue.portion != .full {
                HStack(spacing: 8) {
                    Text(L10n.text("leave.boundary"))
                    DatePicker(L10n.text("leave.boundary"), selection: boundary(range.boundaryMinute), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.field).fixedSize()
                    Spacer()
                }
            }
        }.padding(.vertical, 4)
    }

    private func portionPicker(_ range: Binding<LeaveRange>) -> some View {
        Picker(L10n.text("leave.portion"), selection: range.portion) {
            ForEach(LeavePortion.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).fixedSize()
    }
    private func payPicker(_ range: Binding<LeaveRange>) -> some View {
        Picker(L10n.text("leave.pay"), selection: range.pay) {
            ForEach(LeavePay.allCases) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).fixedSize()
    }
    private func kindPicker(_ range: Binding<LeaveRange>) -> some View {
        HStack(spacing: 4) {
            ForEach(LeaveKind.allCases) { kind in
                let selected = (range.wrappedValue.kind ?? .general) == kind
                Button {
                    // 一次写回整份值，避免第二次属性写入覆盖同一事务里刚选择的类型。
                    var value = range.wrappedValue
                    value.kind = kind == .general ? nil : kind
                    if kind == .compensatory { value.pay = .paid }
                    range.wrappedValue = value
                } label: {
                    Text(kind.title).font(.body.weight(selected ? .semibold : .medium))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .foregroundStyle(selected ? Color.black : kind.color)
                        .background(kind.color.opacity(selected ? 1 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(kind.color.opacity(selected ? 1 : 0.55)))
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.fixedSize().accessibilityElement(children: .contain).accessibilityLabel(L10n.text("leave.kind.title"))
    }

    private func boundary(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(get: { model.workCalendar.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: draft.base.start) ?? draft.base.start },
            set: { minute.wrappedValue = model.workCalendar.component(.hour, from: $0) * 60 + model.workCalendar.component(.minute, from: $0) })
    }

    private func save(finish: Bool) {
        do {
            try model.saveLeaveRequest(&draft, finish: finish)
            message = L10n.text("leave.saved_feedback"); isError = false
        } catch { message = error.localizedDescription; isError = true }
    }

}

/// 隔离测试复用同一编辑区；正式设置页直接嵌入上面的区块。
struct LeaveManagementView: View {
    @ObservedObject var model: DayPerkModel
    @State private var draft = LeaveRequestDraft()
    @State private var error = ""
    @State private var selectedDate = Date()
    var body: some View {
        Form {
            Section {
                HolidayCalendarView(overrides: Binding(get: { model.configuration.dateOverrides }, set: { model.updateWorkdayOverrides($0) }),
                    selectedDate: Binding(get: { draft.isSelecting ? draft.selection.start : selectedDate }, set: { if draft.isSelecting { draft.selection.start = $0 } else { selectedDate = $0; draft.base.start = $0 } }), overtimeDates: model.overtimeDates, region: model.regional.region,
                    subdivision: model.regional.selectedPolicy.subdivision, rhythm: model.rhythm,
                    weekdays: Set(model.schedule.workdays.map(\.calendarWeekday)), workCalendar: model.workCalendar,
                    leaveDays: model.leaveDays, selectionEnd: draft.isSelecting ? $draft.selection.end : nil,
                    confirmedRange: draft.isSelecting ? draft.confirmedBase.map { $0.start ... $0.end } : nil,
                    selectionBounds: draft.isSelecting ? draft.selectionBounds : nil, selectionID: draft.isSelecting ? draft.selectedSegmentID : nil)
            } header: {
                HStack {
                    Text(L10n.text("schedule.calendar"))
                    Spacer()
                    Button(L10n.text(draft.isSelecting ? (draft.confirmedBase == nil ? "leave.cancel_selection" : "leave.finish_adjustments") : "leave.begin")) {
                        if draft.isSelecting {
                            do { if draft.confirmedBase != nil { try model.saveLeaveRequest(&draft, finish: true) } else { draft.isSelecting = false } }
                            catch { self.error = error.localizedDescription }
                        }
                        else { draft.beginSelection() }
                    }
                }
            }
            LeaveEditorSections(model: model, draft: $draft)
        }.formStyle(.grouped).actionFeedback($error, isError: true).environment(\.timeZone, model.workCalendar.timeZone)
    }
}

/// 整段为底轨，分段叠在底轨内，日期文字单独显示。
struct LeaveRequestTimeline: View {
    var request: LeaveRequest
    var selectedSegmentID: UUID? = nil
    var calendar: Calendar
    static func label(_ range: LeaveRange, calendar: Calendar) -> String {
        let first = WorkPlan.dayKey(range.start, calendar: calendar), last = WorkPlan.dayKey(range.end, calendar: calendar)
        return first == last ? first : first + " – " + last
    }
    var body: some View {
        GeometryReader { geometry in
            let start = calendar.startOfDay(for: request.base.start)
            let count = max(1, (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: request.base.end)).day ?? 0) + 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.cyan.opacity(0.25)).frame(height: 8)
                ForEach(request.segments) { segment in
                    let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: segment.start)).day ?? 0
                    let length = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: segment.start), to: calendar.startOfDay(for: segment.end)).day ?? 0) + 1)
                    Capsule().fill(segment.pay == .paid ? Color.green : Color.orange)
                        .frame(width: max(4, geometry.size.width * CGFloat(length) / CGFloat(count)), height: selectedSegmentID == segment.id ? 12 : 8)
                        .offset(x: geometry.size.width * CGFloat(offset) / CGFloat(count))
                }
            }.frame(height: 16)
        }.frame(height: 16).accessibilityLabel(LeaveRequestTimeline.label(request.base, calendar: calendar))
    }
}
