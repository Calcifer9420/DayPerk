import AppKit
import Charts
import SwiftUI

extension WorkStatusDefinition {
    var color: Color {
        let value = UInt64(colorHex, radix: 16) ?? 0x2ACDEB
        let rgb = colorHex.count == 8 ? value >> 8 : value
        let opacity = colorHex.count == 8 ? Double(value & 255) / 255 : 1
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: opacity)
    }
    static func hex(_ color: Color) -> String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .systemCyan
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        let value = String(format: "%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
        return byte(rgb.alphaComponent) == 255 ? value : value + String(format: "%02X", byte(rgb.alphaComponent))
    }
    func menuSwatch(selected: Bool) -> NSImage {
        let fill = NSColor(color)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            fill.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)).fill()
            if selected {
                NSColor.white.setStroke()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 4.5, y: 8)); check.line(to: NSPoint(x: 7, y: 5.5)); check.line(to: NSPoint(x: 11.5, y: 10.5))
                check.lineWidth = 1.8; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
            }
            return true
        }
        // 原生菜单会把模板符号统一着色，实色图保留用户选择的颜色。
        image.isTemplate = false
        return image
    }
}

struct WorkStatusMenu: View {
    @ObservedObject var controller: WorkStatusController
    var body: some View {
        Menu {
            ForEach(controller.data.available) { status in
                Button { controller.select(status.id) } label: {
                    Label {
                        Text(verbatim: status.title)
                    } icon: { Image(nsImage: status.menuSwatch(selected: status.id == controller.data.selectedID)).renderingMode(.original) }
                }
                .accessibilityLabel(status.title + " · " + L10n.text(status.isWorking ? "workstatus.working" : "workstatus.nonworking"))
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(controller.data.selected.color).frame(width: 7, height: 7)
                Text(verbatim: controller.data.selected.title).lineLimit(1).truncationMode(.tail)
            }.frame(maxWidth: 94)
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.text("workstatus.current"))
            .accessibilityValue(Text(verbatim: controller.data.selected.title))
            .help(L10n.text("workstatus.help"))
    }
}

struct WorkStatusSettingsView: View {
    @ObservedObject var controller: WorkStatusController
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingID: String?
    @State private var name = ""
    @State private var color: Color = .cyan
    @State private var showsColorPicker = false
    @State private var isWorking = true
    @State private var error = ""
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowHeights: [String: CGFloat] = [:]
    @GestureState private var draggingHandle = false
    private var statuses: [WorkStatusDefinition] { controller.data.available }
    private var reorderAnimation: Animation? { reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.85) }
    private var dragLayout: DragReorderLayout? {
        guard let source = statuses.firstIndex(where: { $0.id == draggingID }) else { return nil }
        return DragReorderLayout(source: source, translation: dragTranslation, heights: statuses.map { rowHeights[$0.id] ?? 0 }, spacing: 0)
    }
    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L10n.text("workstatus.enable"))
                    InfoHelp(text: L10n.text("workstatus.help")).frame(width: 18, height: 18)
                    Spacer()
                    Toggle(L10n.text("workstatus.enable"), isOn: Binding(get: { controller.data.enabled }, set: { controller.setEnabled($0) }))
                        .labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false))
                        .accessibilityLabel(L10n.text("workstatus.enable"))
                }
            }
            Section(L10n.text("workstatus.options")) {
                VStack(spacing: 0) {
                    ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                        statusRow(status, index: index)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[status.id] = $0 }
                            .offset(y: dragLayout?.offset(at: index) ?? 0)
                            .zIndex(draggingID == status.id ? 1 : 0)
                            .animation(draggingID == status.id ? nil : reorderAnimation, value: dragLayout?.target)
                    }
                }
            }
            Section {
                TextField(L10n.text("workstatus.name"), text: $name).textFieldStyle(.roundedBorder).disabled(editingID == WorkStatusDefinition.rest.id)
                HStack(spacing: 10) {
                    Text(L10n.text("workstatus.kind"))
                    Picker(L10n.text("workstatus.kind"), selection: $isWorking) {
                        Text(L10n.text("workstatus.working")).tag(true)
                        Text(L10n.text("workstatus.nonworking")).tag(false)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                        .disabled(editingID == WorkStatusDefinition.rest.id)
                    Spacer(minLength: 24)
                    Text(L10n.text("workstatus.color"))
                    Button { showsColorPicker.toggle() } label: {
                        StatusColorSample(color: color).frame(width: 38, height: 20)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.text("workstatus.color"))
                        .popover(isPresented: $showsColorPicker, arrowEdge: .trailing) {
                            StatusColorPalette(color: $color) { showsColorPicker = false }
                        }
                }
                if editingID != nil { HStack {
                    Spacer()
                    if let editingID {
                        Button(role: .destructive) {
                            do { try controller.remove(editingID); reset(); ActionToastCenter.shared.show(L10n.text("workstatus.removed")) }
                            catch { self.error = error.localizedDescription }
                        } label: { Image(systemName: "trash") }
                            .disabled(!canRemove(editingID))
                            .accessibilityLabel(L10n.format("workstatus.remove", name))
                            .help(editingID == WorkStatusDefinition.rest.id ? L10n.text("workstatus.default_rest") : L10n.format("workstatus.remove", name))
                        Button(L10n.text("ui.cancel.2cd0f3be"), systemImage: "xmark", action: reset)
                            .labelStyle(.iconOnly).help(L10n.text("ui.cancel.2cd0f3be"))
                    }
                    saveButton
                } }
            } header: {
                HStack {
                    Text(L10n.text(editingID == nil ? "workstatus.add" : "workstatus.edit"))
                    Spacer()
                    if editingID == nil { saveButton }
                }
            }
        }.formStyle(.grouped).actionFeedback($error, isError: true)
            .onChange(of: draggingHandle) { _, active in
                if !active, draggingID != nil { cancelDrag() }
            }
            .onDisappear { showsColorPicker = false; cancelDrag() }
    }

    private var saveButton: some View {
        Button(L10n.text(editingID == nil ? "workstatus.add" : "workstatus.save"), systemImage: editingID == nil ? "plus" : "checkmark") {
            do { try controller.saveDefinition(id: editingID, name: name, colorHex: WorkStatusDefinition.hex(color), isWorking: isWorking); reset(); ActionToastCenter.shared.show(L10n.text("action.saved")) }
            catch { self.error = error.localizedDescription }
        }.labelStyle(.iconOnly).help(L10n.text(editingID == nil ? "workstatus.add" : "workstatus.save"))
            .buttonStyle(BrewButtonStyle(prominent: true)).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func statusRow(_ status: WorkStatusDefinition, index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(status.color).frame(width: 12, height: 12)
                Text(verbatim: status.title).lineLimit(2)
                Text(L10n.text(status.isWorking ? "workstatus.working" : "workstatus.nonworking"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") {
                    showsColorPicker = false; editingID = status.id; name = status.title; color = status.color; isWorking = status.isWorking; error = ""
                }.labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656") + " · " + status.title)
                Button(role: status.isRest ? nil : .destructive) {
                    do { try controller.remove(status.id); if editingID == status.id { reset() }; ActionToastCenter.shared.show(L10n.text("workstatus.removed")) }
                    catch { self.error = error.localizedDescription }
                } label: { Image(systemName: status.isRest ? "lock.fill" : "trash").frame(width: 16, height: 16) }
                    .disabled(!canRemove(status.id))
                    .accessibilityLabel(status.isRest ? L10n.text("workstatus.default_rest") : L10n.format("workstatus.remove", status.title))
                    .help(status.isRest ? L10n.text("workstatus.default_rest") : L10n.format("workstatus.remove", status.title))
                Button {} label: { Image(systemName: "line.3.horizontal").frame(width: 16, height: 16) }
                    .buttonStyle(BrewButtonStyle())
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                        .updating($draggingHandle) { value, active, _ in
                            if case .second(true, _) = value { active = true }
                        }
                        .onChanged { value in
                            guard case let .second(true, drag) = value else { return }
                            if draggingID == nil { draggingID = status.id; showsColorPicker = false }
                            dragTranslation = drag?.translation.height ?? 0
                            NSCursor.closedHand.set()
                        }
                        .onEnded { value in
                            if case let .second(true, drag) = value { dragTranslation = drag?.translation.height ?? 0; finishDrag() }
                            else { cancelDrag() }
                            NSCursor.openHand.set()
                        })
                    .onHover { inside in
                        if draggingID == nil { (inside ? NSCursor.openHand : .arrow).set() }
                    }
                    .help(L10n.text("workstatus.drag_reorder"))
                    .accessibilityElement().accessibilityLabel(L10n.text("workstatus.drag_reorder") + ": " + status.title)
                    .accessibilityAction(named: Text(L10n.text("workstatus.move_up"))) { move(status, by: -1) }
                    .accessibilityAction(named: Text(L10n.text("workstatus.move_down"))) { move(status, by: 1) }
            }.padding(.vertical, 10).padding(.horizontal, 6)
            if index < statuses.count - 1 { Divider() }
        }
        .background(draggingID == status.id ? appearance.theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(appearance.theme.color.opacity(draggingID == status.id ? 0.9 : 0), lineWidth: 2))
        .shadow(color: .black.opacity(draggingID == status.id ? 0.24 : 0), radius: 8, y: 4)
    }

    private func finishDrag() {
        guard let id = draggingID, let layout = dragLayout else { cancelDrag(); return }
        let target = statuses[layout.target].id
        withAnimation(reorderAnimation) {
            if controller.move(id, to: target) { ActionToastCenter.shared.show(L10n.text("workstatus.reordered")) }
            draggingID = nil; dragTranslation = 0
        }
    }

    private func cancelDrag() {
        withAnimation(reorderAnimation) { draggingID = nil; dragTranslation = 0 }
        NSCursor.arrow.set()
    }

    private func move(_ status: WorkStatusDefinition, by offset: Int) {
        guard let index = statuses.firstIndex(where: { $0.id == status.id }), statuses.indices.contains(index + offset) else { return }
        withAnimation(reorderAnimation) {
            if controller.move(status.id, to: statuses[index + offset].id) { ActionToastCenter.shared.show(L10n.text("workstatus.reordered")) }
        }
    }
    private func canRemove(_ id: String) -> Bool {
        guard let status = controller.data.available.first(where: { $0.id == id }), !status.isRest else { return false }
        return !status.isWorking || controller.data.available.filter(\.isWorking).count > 1
    }
    private func reset() { showsColorPicker = false; editingID = nil; name = ""; color = .cyan; isWorking = true; error = "" }
}

struct WorkStatusStatisticsView: View {
    @ObservedObject var controller: WorkStatusController
    var interval: DateInterval
    var plan: WorkPlan
    var days: [WorkDayTotal]
    var calendar: Calendar
    var day: Date? = nil
    var daySelection: Binding<Date?>? = nil
    var selectionBounds: ClosedRange<Date>? = nil
    var snapshotDate: Date? = nil
    @Environment(\.locale) private var locale
    @State private var hoveredStatus: String?
    @State private var hoveredSegment: UUID?
    var body: some View {
        Group {
            if let snapshotDate { content(at: snapshotDate) }
            else { TimelineView(.periodic(from: Date(), by: 1)) { context in content(at: context.date) } }
        }
    }
    private func content(at date: Date) -> some View {
            let segments = controller.recordedSegments(at: date)
            let timeline = day == nil ? nil : WorkStatusTimeline.make(segments: segments, days: days, plan: plan, interval: interval, calendar: calendar, now: date)
            let totals = WorkStatusReport.totals(segments, definitions: controller.data.definitions, interval: timeline?.interval ?? interval)
            let sum = totals.reduce(0) { $0 + $1.seconds }
            return VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if snapshotDate == nil { InfoHelp(text: L10n.text("workstatus.report_help")).frame(width: 18, height: 18) }
                    Spacer()
                    if let daySelection {
                        if daySelection.wrappedValue != nil {
                            Button(L10n.text("workstatus.all_days"), systemImage: "xmark") { daySelection.wrappedValue = nil }
                                .labelStyle(.iconOnly).help(L10n.text("workstatus.all_days"))
                        }
                        BrewDatePicker(title: L10n.text("workstatus.choose_day"), selection: Binding(
                            get: { daySelection.wrappedValue ?? interval.start }, set: { daySelection.wrappedValue = $0 }),
                            calendar: calendar, bounds: selectionBounds, showsLabel: false, iconOnly: true)
                            .help(L10n.text("workstatus.choose_day"))
                    }
                }
                if totals.isEmpty {
                    Text(L10n.text("workstatus.empty")).foregroundStyle(.secondary).padding(.vertical, 16)
                } else {
                    HStack(alignment: .center, spacing: 32) {
                        Chart(totals) { row in
                            SectorMark(angle: .value(L10n.text("workstatus.duration"), row.seconds), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(row.definition.color.opacity(hoveredStatus == nil || hoveredStatus == row.id ? 1 : 0.25)).cornerRadius(4)
                                .accessibilityLabel(Text(verbatim: row.definition.title))
                                .accessibilityValue(WorkDurationInput.formatSeconds(WorkDurationInput.wholeSeconds(row.seconds)))
                        }.chartLegend(.hidden).frame(width: 190, height: 190)
                            .overlay { Text(WorkDurationInput.formatSeconds(totals.reduce(0) { $0 + WorkDurationInput.wholeSeconds($1.seconds) })).font(.callout.monospacedDigit()).accessibilityLabel(L10n.text("workstatus.total")) }
                            .overlay {
                                GeometryReader { geometry in
                                    Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                                        hoveredSegment = nil
                                        switch phase {
                                        case .active(let point):
                                            let frame = CGRect(origin: .zero, size: geometry.size)
                                            let x = point.x - frame.midX, y = point.y - frame.midY
                                            let radius = hypot(x, y), outer = min(frame.width, frame.height) / 2
                                            guard radius >= outer * 0.62, radius <= outer else { hoveredStatus = nil; return }
                                            let angle = atan2(x, -y)
                                            hoveredStatus = WorkStatusTimeline.status(at: (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi), totals: totals)
                                        case .ended: hoveredStatus = nil
                                        }
                                    }
                                }
                            }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(totals) { row in
                                HStack(spacing: 8) {
                                    Circle().fill(row.definition.color).frame(width: 9, height: 9)
                                    Text(verbatim: row.definition.title).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(WorkDurationInput.formatSeconds(WorkDurationInput.wholeSeconds(row.seconds))).monospacedDigit()
                                    Text((row.seconds / sum).formatted(.percent.locale(locale).precision(.fractionLength(0))))
                                        .foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
                                }.padding(.vertical, 2).contentShape(Rectangle())
                                    .opacity(hoveredStatus == nil || hoveredStatus == row.id ? 1 : 0.35)
                                    .onHover { inside in
                                        hoveredSegment = nil
                                        if inside { hoveredStatus = row.id }
                                        else if hoveredStatus == row.id { hoveredStatus = nil }
                                    }
                            }
                        }.frame(width: 280)
                    }.frame(maxWidth: .infinity, alignment: .center)
                }
                if let timeline {
                    Divider()
                    WorkStatusTimelineView(timeline: timeline, definitions: controller.data.definitions,
                        calendar: calendar, hoveredStatus: $hoveredStatus, hoveredSegment: $hoveredSegment)
                }
            }.padding(18)
                .background(AppearanceSettings.shared.theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: interval) { _, _ in hoveredStatus = nil; hoveredSegment = nil }
        }

    private var title: String {
        guard let day else { return L10n.text("workstatus.distribution") }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM.dd"
        return L10n.format("workstatus.day_distribution", formatter.string(from: day))
    }
}
