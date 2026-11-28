import Foundation

struct WorkStatusTimeline {
    var interval: DateInterval
    var segments: [WorkStatusSegment]

    static func make(segments: [WorkStatusSegment], days: [WorkDayTotal], plan: WorkPlan,
                     interval: DateInterval, calendar: Calendar, now: Date) -> Self? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: interval.start), interval.end == nextDay else { return nil }
        let inReport = segments.filter { $0.end > interval.start && $0.start < interval.end }
        var cursor = interval.start
        var bounds: DateInterval?
        let records = Dictionary(days.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        while cursor < interval.end {
            let key = plan.businessDayKey(cursor, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            let record = records[key]
            let recorded = inReport.filter { $0.end > cursor && $0.start < next }
            if plan.isWorkday(cursor, calendar: calendar) || !recorded.isEmpty || record?.clockedInAt != nil || record?.settledAt != nil {
                let shift = plan.scheduledInterval(for: key, calendar: calendar)
                let plannedStart = record?.scheduledStart ?? shift?.start ?? cursor
                let plannedEnd = record?.scheduledEnd ?? shift?.end ?? next
                let start = min(plannedStart, record?.clockedInAt ?? plannedStart, recorded.map { max($0.start, cursor) }.min() ?? plannedStart)
                let end = max(plannedEnd, record?.settledAt ?? plannedEnd, recorded.map(\.end).max() ?? plannedEnd)
                if let previous = bounds { bounds = DateInterval(start: min(previous.start, start), end: max(previous.end, end)) }
                else { bounds = DateInterval(start: start, end: end) }
            }
            cursor = next
        }
        guard var bounds else { return nil }
        // 跨夜班次可能越过业务日边界，连着记录的片段保留到实际结束；空档不追填。
        for segment in segments.filter({ $0.end > bounds.start && $0.seconds > 0 }).sorted(by: { $0.start < $1.start }) {
            if segment.start > bounds.end { break }
            if segment.end > bounds.end { bounds.end = segment.end }
        }
        let visible = segments.compactMap { segment -> WorkStatusSegment? in
            let start = max(segment.start, bounds.start), end = min(segment.end, bounds.end)
            guard end > start else { return nil }
            var value = segment; value.start = start; value.end = end
            return value
        }.sorted { $0.start < $1.start }
        return Self(interval: bounds, segments: visible)
    }

    func segment(at fraction: Double) -> WorkStatusSegment? {
        guard fraction.isFinite, (0 ... 1).contains(fraction) else { return nil }
        let date = interval.start.addingTimeInterval(fraction * interval.duration)
        return segments.first { date >= $0.start && date < $0.end }
    }

    static func status(at fraction: Double, totals: [WorkStatusTotal]) -> String? {
        guard fraction.isFinite, (0 ..< 1).contains(fraction) else { return nil }
        let value = totals.reduce(0) { $0 + $1.seconds } * fraction
        var end = 0.0
        return totals.first { row in end += row.seconds; return value < end }?.id
    }
}
