import Combine
import Foundation

struct WorkStatusDefinition: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var colorHex: String
    var archived = false
    var countsAsWork: Bool?
    var isRest: Bool { id == "rest" }
    var isWorking: Bool { !isRest && (countsAsWork ?? true) }
    var usesPresetName: Bool {
        guard let name else { return true }
        guard Self.presets.contains(where: { $0.id == id }) else { return false }
        // 旧版改颜色时可能保存了内置译名，显示时仍跟随语言，不改用户自定名称。
        return AppLanguage.allCases.contains { $0 != .system && LocalizationManager.shared.string(for: "workstatus.preset." + id, language: $0.rawValue) == name }
    }
    var title: String { usesPresetName ? L10n.text("workstatus.preset." + id) : name! }
    static let rest = Self(id: "rest", colorHex: "A3ADB8", countsAsWork: false)
    static let presets: [Self] = zip(["focus", "busy", "repetitive", "lowvalue", "meaningful", "challenging"],
                                    ["2ACDEB", "FF9F0A", "8E8E93", "FF6961", "32D174", "BF87FF"])
        .map { Self(id: $0.0, colorHex: $0.1) } + [rest]
}

struct WorkStatusSegment: Codable, Equatable, Identifiable {
    var id = UUID()
    var statusID: String
    var start: Date
    var end: Date
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

struct WorkStatusData: Codable, Equatable {
    var enabled = false
    var definitions = WorkStatusDefinition.presets
    var selectedID = "focus"
    var segments: [WorkStatusSegment] = []
    var available: [WorkStatusDefinition] { definitions.filter { !$0.archived } }
    var selected: WorkStatusDefinition { definitions.first { $0.id == selectedID } ?? WorkStatusDefinition.presets[0] }

    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, definitions, selectedID, segments }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        definitions = try values.decode([WorkStatusDefinition].self, forKey: .definitions)
        if !definitions.contains(where: \.isRest) { definitions.append(.rest) }
        selectedID = try values.decode(String.self, forKey: .selectedID)
        segments = try values.decode([WorkStatusSegment].self, forKey: .segments)
    }

    func validate() throws {
        guard !available.isEmpty, definitions.count <= 201, segments.count <= 200_000,
              Set(definitions.map(\.id)).count == definitions.count,
              Set(segments.map(\.id)).count == segments.count,
              available.contains(where: { $0.id == selectedID }),
              available.contains(where: \.isWorking),
              !definitions.contains(where: { $0.isRest && ($0.archived || $0.countsAsWork == true || $0.name != nil) }) else { throw Self.invalid() }
        for definition in definitions {
            guard !definition.id.isEmpty, definition.id.count <= 128,
                  definition.colorHex.range(of: "^[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", options: .regularExpression) != nil,
                  definition.name.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 })
                    ?? WorkStatusDefinition.presets.contains(where: { $0.id == definition.id }) else { throw Self.invalid() }
        }
        let ids = Set(definitions.map(\.id))
        let ordered = segments.sorted { $0.start < $1.start }
        for (index, segment) in ordered.enumerated() {
            guard ids.contains(segment.statusID), segment.start.timeIntervalSince1970.isFinite,
                  segment.end.timeIntervalSince1970.isFinite, segment.end >= segment.start,
                  index == 0 || ordered[index - 1].end <= segment.start else { throw Self.invalid() }
        }
    }
    static func invalid() -> DayPerkInputError { DayPerkInputError(message: L10n.text("workstatus.invalid")) }
}

/// 记录在岗期间的工作与休息；切换类型通过现有计费入口联动，不追填历史。
final class WorkStatusController: ObservableObject {
    static let storageKey = "dayperkWorkStatusV1"
    @Published private(set) var data: WorkStatusData
    private let defaults: any UserDataPreferences
    private var active: WorkStatusSegment?
    private var working = false
    private var onDuty = false
    private var lastWorkingID = "focus"
    private var requestingWorkChange = false
    var workingRequested: ((Bool, Date) -> Void)?
    private var lastPulse = Date()
    private var lastSaved = Date.distantPast

    init(defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(WorkStatusData.self, from: bytes), (try? saved.validate()) != nil {
            data = saved
        } else { data = WorkStatusData() }
        lastWorkingID = data.selected.isWorking ? data.selectedID : (data.available.first(where: \.isWorking)?.id ?? "focus")
    }

    func updateWorking(_ enabled: Bool, onDuty: Bool = false, at now: Date = Date()) {
        working = enabled; self.onDuty = enabled || onDuty
        guard data.enabled, !requestingWorkChange else { return }
        guard self.onDuty else {
            close(at: now); checkpoint(at: now)
            return
        }
        let selectedID: String
        if enabled {
            selectedID = data.selected.isWorking ? data.selectedID : (data.available.first { $0.id == lastWorkingID && $0.isWorking }?.id ?? data.available.first(where: \.isWorking)!.id)
            lastWorkingID = selectedID
        } else {
            if data.selected.isWorking { lastWorkingID = data.selectedID }
            selectedID = data.selected.isWorking ? WorkStatusDefinition.rest.id : data.selectedID
        }
        if active?.statusID != selectedID || now.timeIntervalSince(lastPulse) > 5 { close(at: now) }
        if data.selectedID != selectedID { data.selectedID = selectedID }
        if active == nil { active = WorkStatusSegment(statusID: selectedID, start: now, end: now) }
        if var current = active { current.end = max(current.end, now); active = current }
        lastPulse = now
        if now.timeIntervalSince(lastSaved) >= 10 { checkpoint(at: now) }
    }

    func setEnabled(_ enabled: Bool, at now: Date = Date()) {
        guard enabled != data.enabled else { return }
        close(at: now)
        data.enabled = enabled
        if enabled { updateWorking(working, onDuty: onDuty, at: now) }
        checkpoint(at: now)
    }

    func select(_ id: String, at now: Date = Date()) {
        guard data.available.contains(where: { $0.id == id }), id != data.selectedID else { return }
        close(at: now); data.selectedID = id
        if data.selected.isWorking { lastWorkingID = id }
        if data.enabled {
            requestWorking(at: now)
        }
        checkpoint(at: now)
    }

    func saveDefinition(id: String? = nil, name: String, colorHex: String, isWorking: Bool = true, at now: Date = Date()) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = data
        if let index = next.definitions.firstIndex(where: { $0.id == id }) {
            let definition = next.definitions[index]
            // 内置名称未改动时保留翻译键，改颜色或类型不会把当前译名写死。
            next.definitions[index].name = definition.isRest || (definition.usesPresetName && name == definition.title) ? nil : name
            next.definitions[index].colorHex = colorHex
            next.definitions[index].countsAsWork = next.definitions[index].isRest ? false : isWorking
        } else { next.definitions.append(WorkStatusDefinition(id: UUID().uuidString, name: name, colorHex: colorHex, countsAsWork: isWorking)) }
        try next.validate()
        let typeChanged = next.selected.isWorking != data.selected.isWorking
        if typeChanged { close(at: now) }
        data = next
        if typeChanged, data.enabled {
            requestWorking(at: now)
        }
        checkpoint(at: now)
    }

    func remove(_ id: String, at now: Date = Date()) throws {
        guard let index = data.definitions.firstIndex(where: { $0.id == id }), !data.definitions[index].isRest,
              data.available.contains(where: { $0.id != id && $0.isWorking }) else { throw WorkStatusData.invalid() }
        if data.selectedID == id, let replacement = data.available.first(where: { $0.id != id && $0.isWorking == data.selected.isWorking }) ?? data.available.first(where: { $0.id != id }) { select(replacement.id, at: now) }
        data.definitions[index].archived = true
        checkpoint(at: now)
    }

    @discardableResult
    func move(_ id: String, to targetID: String, at now: Date = Date()) -> Bool {
        guard id != targetID,
              let source = data.definitions.firstIndex(where: { $0.id == id && !$0.archived }),
              let target = data.definitions.firstIndex(where: { $0.id == targetID && !$0.archived }) else { return false }
        var definitions = data.definitions
        definitions.insert(definitions.remove(at: source), at: target)
        data.definitions = definitions
        checkpoint(at: now)
        return true
    }

    func recordedSegments(at now: Date = Date()) -> [WorkStatusSegment] {
        guard var current = active else { return data.segments }
        current.end = max(current.end, min(now, lastPulse.addingTimeInterval(5)))
        return data.segments + (current.seconds > 0 ? [current] : [])
    }

    func checkpoint(at now: Date = Date()) {
        var snapshot = data; snapshot.segments = recordedSegments(at: now)
        if let encoded = try? JSONEncoder().encode(snapshot) { defaults.set(encoded, forKey: Self.storageKey); lastSaved = now }
    }

    private func requestWorking(at now: Date) {
        // 计费状态会发布中间步骤，联动完成前保留用户刚选的具体状态。
        requestingWorkChange = true
        workingRequested?(data.selected.isWorking, now)
        requestingWorkChange = false
        updateWorking(working, onDuty: onDuty, at: now)
    }

    private func close(at now: Date) {
        guard var current = active else { return }
        current.end = max(current.end, min(now, lastPulse.addingTimeInterval(5)))
        if current.seconds > 0 { data.segments.append(current) }
        active = nil
    }
}

struct WorkStatusTotal: Identifiable {
    var definition: WorkStatusDefinition
    var seconds: Double
    var id: String { definition.id }
}

enum WorkStatusReport {
    static func totals(_ segments: [WorkStatusSegment], definitions: [WorkStatusDefinition], interval: DateInterval) -> [WorkStatusTotal] {
        var seconds: [String: Double] = [:]
        for segment in segments {
            let duration = min(segment.end, interval.end).timeIntervalSince(max(segment.start, interval.start))
            if duration > 0 { seconds[segment.statusID, default: 0] += duration }
        }
        return definitions.compactMap { definition in
            guard let value = seconds[definition.id], value > 0 else { return nil }
            return WorkStatusTotal(definition: definition, seconds: value)
        }.sorted { $0.seconds > $1.seconds }
    }

    static func interval(containing date: Date, period: WorkReportPeriod, calendar: Calendar, dayStartMinute: Int) -> DateInterval {
        let base = WorkReport.make(days: [], containing: date, period: period, calendar: calendar).interval
        func boundary(_ day: Date) -> Date {
            calendar.date(bySettingHour: dayStartMinute / 60, minute: dayStartMinute % 60, second: 0, of: day) ?? day
        }
        return DateInterval(start: boundary(base.start), end: boundary(base.end))
    }
}
