import SwiftUI

struct WorkStatusTimelineView: View {
    var timeline: WorkStatusTimeline
    var definitions: [WorkStatusDefinition]
    var calendar: Calendar
    @Binding var hoveredStatus: String?
    @Binding var hoveredSegment: UUID?
    @Environment(\.locale) private var locale

    private var selected: WorkStatusDefinition? { definitions.first { $0.id == hoveredStatus } }
    private var selectedSegment: WorkStatusSegment? { timeline.segments.first { $0.id == hoveredSegment } }
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        let value = formatter.string(from: date)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: timeline.interval.start), to: calendar.startOfDay(for: date)).day ?? 0
        if offset == 1 { return L10n.format("workstatus.timeline_next_day", value) }
        return offset > 1 ? L10n.format("workstatus.timeline_day_offset", String(offset), value) : value
    }
    private func definition(_ segment: WorkStatusSegment) -> WorkStatusDefinition? { definitions.first { $0.id == segment.statusID } }
    private func duration(_ seconds: Double) -> String { WorkDurationInput.formatSeconds(WorkDurationInput.wholeSeconds(seconds)) }

    private func piece(_ segment: WorkStatusSegment, width: CGFloat) -> some View {
        let highlighted = hoveredStatus == nil || hoveredStatus == segment.statusID
        let color: Color = definition(segment)?.color ?? .secondary
        let length = CGFloat(max(0.5, Double(width) * segment.seconds / timeline.interval.duration))
        let offset = CGFloat(Double(width) * segment.start.timeIntervalSince(timeline.interval.start) / timeline.interval.duration)
        let title = definition(segment)?.title ?? ""
        let value = time(segment.start) + " – " + time(segment.end) + ", " + duration(segment.seconds)
        return RoundedRectangle(cornerRadius: 2).fill(color).opacity(highlighted ? 1 : 0.16)
            .frame(width: length, height: hoveredStatus == segment.statusID ? 28 : 22).offset(x: offset)
            .accessibilityLabel(Text(verbatim: title)).accessibilityValue(value)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(L10n.text("workstatus.timeline")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                if let selected {
                    Circle().fill(selected.color).frame(width: 8, height: 8)
                    Text(verbatim: selected.title).lineLimit(1)
                    if let segment = selectedSegment {
                        Text(time(segment.start) + " – " + time(segment.end)).monospacedDigit()
                        Text(duration(segment.seconds)).monospacedDigit()
                    } else {
                        let values = timeline.segments.filter { $0.statusID == selected.id }
                        Text(duration(values.reduce(0) { $0 + $1.seconds })).monospacedDigit()
                        Text(L10n.format("workstatus.timeline_segments", String(values.count))).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.text("workstatus.timeline_hint")).foregroundStyle(.secondary)
                }
            }.font(.caption).lineLimit(1).frame(height: 22)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.07))
                    ForEach(timeline.segments) { segment in
                        piece(segment, width: geometry.size.width)
                    }
                }.frame(height: 28).clipShape(RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let segment = timeline.segment(at: point.x / max(1, geometry.size.width))
                            hoveredSegment = segment?.id; hoveredStatus = segment?.statusID
                        case .ended: hoveredSegment = nil; hoveredStatus = nil
                        }
                    }
            }.frame(height: 28).accessibilityElement(children: .contain).accessibilityLabel(L10n.text("workstatus.timeline"))
            HStack {
                Text(time(timeline.interval.start))
                Spacer()
                Text(time(timeline.interval.start.addingTimeInterval(timeline.interval.duration / 2)))
                Spacer()
                Text(time(timeline.interval.end))
            }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
