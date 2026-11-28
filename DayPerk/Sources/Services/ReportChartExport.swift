import AppKit
import SwiftUI

enum ReportChartExport {
    @MainActor static func data(controller: WorkStatusController, interval: DateInterval, plan: WorkPlan, days: [WorkDayTotal], locale: Locale, calendar: Calendar, day: Date? = nil, now: Date = Date()) throws -> Data {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = calendar.timeZone; formatter.dateStyle = .medium
        let content = VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("workstatus.title")).font(.title2.bold())
            Text(day.map { formatter.string(from: $0) } ?? (formatter.string(from: interval.start) + " – " + formatter.string(from: calendar.startOfDay(for: interval.end).addingTimeInterval(-1)))).foregroundStyle(.secondary)
            WorkStatusStatisticsView(controller: controller, interval: interval, plan: plan, days: days, calendar: calendar, day: day, snapshotDate: now)
        }.padding(28).frame(width: 800).background(AppearanceSettings.shared.theme.canvas)
            .environment(\.locale, locale).preferredColorScheme(.dark).foregroundStyle(.white)
        let renderer = ImageRenderer(content: content); renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
