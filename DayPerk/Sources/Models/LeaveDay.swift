import Foundation

enum LeavePay: String, Codable, CaseIterable, Identifiable {
    case paid, unpaid
    var id: Self { self }
    var title: String { L10n.text("leave." + rawValue) }
}

enum LeavePortion: String, Codable, CaseIterable, Identifiable {
    case full, morning, afternoon
    var id: Self { self }
    var title: String { L10n.text("leave." + rawValue) }
}

enum LeaveKind: String, Codable, CaseIterable, Identifiable {
    case general, compensatory
    var id: Self { self }
    var title: String { L10n.text("leave.kind." + rawValue) }
    func summary(portion: LeavePortion, pay: LeavePay) -> String {
        let value = L10n.format("leave.summary", portion.title, pay.title)
        return self == .compensatory ? title + " · " + value : value
    }
}

/// 扣薪份额与请假覆盖的工时分别计算，不把半天工资误当成一半工时。
struct LeaveDay: Codable, Equatable {
    var morning: LeavePay?
    var afternoon: LeavePay?
    var boundaryMinute: Int?
    var morningKind: LeaveKind?
    var afternoonKind: LeaveKind?
    var isEmpty: Bool { morning == nil && afternoon == nil }
    var absenceFraction: Double { Double([morning, afternoon].compactMap { $0 }.count) / 2 }
    var unpaidFraction: Double { Double([morning, afternoon].filter { $0 == .unpaid }.count) / 2 }
    var paidFraction: Double { absenceFraction - unpaidFraction }
    var payableFraction: Double { 1 - unpaidFraction }
    var isCompensatory: Bool {
        !isEmpty && (morning == nil || morningKind == .compensatory) && (afternoon == nil || afternoonKind == .compensatory)
    }
    var summary: String {
        if let morning, morning == afternoon, (morningKind ?? .general) == (afternoonKind ?? .general) {
            return (morningKind ?? .general).summary(portion: .full, pay: morning)
        }
        return [(LeavePortion.morning, morning, morningKind), (.afternoon, afternoon, afternoonKind)].compactMap { portion, pay, kind in
            pay.map { (kind ?? .general).summary(portion: portion, pay: $0) }
        }.joined(separator: " · ")
    }
    func contains(_ portion: LeavePortion) -> Bool {
        (portion != .afternoon && morning != nil) || (portion != .morning && afternoon != nil)
    }
    mutating func set(_ portion: LeavePortion, pay: LeavePay, kind: LeaveKind = .general) {
        if portion != .afternoon { morning = pay; morningKind = kind == .general ? nil : kind }
        if portion != .morning { afternoon = pay; afternoonKind = kind == .general ? nil : kind }
    }
    mutating func remove(_ portion: LeavePortion) {
        if portion != .afternoon { morning = nil; morningKind = nil }
        if portion != .morning { afternoon = nil; afternoonKind = nil }
    }
}

struct LeaveSummary {
    var paidSeconds: Double = 0
    var unpaidSeconds: Double = 0
    var paidDays: Double = 0
    var unpaidDays: Double = 0
}

struct LeaveRange: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var portion: LeavePortion = .full
    var pay: LeavePay = .paid
    var boundaryMinute = 720
    var kind: LeaveKind?
    var summary: String { (kind ?? .general).summary(portion: portion, pay: pay) }
}

struct LeaveRequestDraft {
    var id = UUID()
    var isSelecting = false
    var base = LeaveRange(start: Date(), end: Date())
    var changes: [LeaveRange] = []
    var confirmedBase: LeaveRange?
    var selectedSegmentID: UUID?
    var excludedPortions: [String: LeavePortion]?
    private var emptySegment: LeaveRange?
    var selection: LeaveRange {
        get { changes.first { $0.id == selectedSegmentID } ?? base }
        set {
            if let index = changes.firstIndex(where: { $0.id == selectedSegmentID }) { changes[index] = newValue }
            else { base = newValue }
        }
    }
    var selectionBounds: ClosedRange<Date>? { selectedSegmentID == nil ? nil : min(base.start, base.end) ... max(base.start, base.end) }
    var request: LeaveRequest { LeaveRequest(id: id, base: base, segments: changes.filter { $0 != emptySegment }, excludedPortions: excludedPortions) }
    mutating func beginSelection() {
        id = UUID(); confirmedBase = nil; selectedSegmentID = nil; emptySegment = nil
        base.end = base.start
        resetAttributes()
        isSelecting = true
    }
    mutating func resetAttributes() {
        base.portion = .full; base.pay = .paid; base.boundaryMinute = 720; base.kind = nil
        changes = []; selectedSegmentID = nil; excludedPortions = nil
    }
    mutating func beginAdjustment() {
        let start = selectedSegmentID == nil ? base.start : selection.end
        confirmedBase = base
        let segment = LeaveRange(start: start, end: start, portion: base.portion, pay: base.pay, boundaryMinute: base.boundaryMinute, kind: base.kind)
        changes.append(segment); selectedSegmentID = segment.id; emptySegment = segment
    }
    mutating func edit(_ request: LeaveRequest, segmentID: UUID? = nil) {
        id = request.id; base = request.base; changes = request.segments
        excludedPortions = request.excludedPortions
        confirmedBase = request.base; selectedSegmentID = segmentID; emptySegment = nil; isSelecting = true
    }
    mutating func confirm(addSegment: Bool = false, finish: Bool = false, persist: (LeaveRequest) throws -> Void) throws {
        try persist(request)
        confirmedBase = base
        if addSegment || finish {
            let empty = emptySegment
            changes.removeAll { $0 == empty }
            if !changes.contains(where: { $0.id == selectedSegmentID }) { selectedSegmentID = nil }
            emptySegment = nil
        }
        if addSegment { beginAdjustment() }
        if finish { isSelecting = false }
    }
}

/// 卡片保存原始整段和分段，逐日账本仅用于结算；删掉分段会恢复整段默认值。
struct LeaveRequest: Codable, Equatable, Identifiable {
    var id = UUID()
    var base: LeaveRange
    var segments: [LeaveRange] = []
    // 被后来日期安排覆盖的部分永久移除，删除新安排时也不会恢复。
    var excludedPortions: [String: LeavePortion]?
}

enum LeaveRequests {
    static let storageKey = "dayperkLeaveRequestsV1"
    static func validate(_ requests: [LeaveRequest], calendar: Calendar = .current) throws {
        guard requests.count <= 3660, Set(requests.map(\.id)).count == requests.count else { throw invalid() }
        for request in requests {
            let first = WorkPlan.dayKey(request.base.start, calendar: calendar)
            let last = WorkPlan.dayKey(request.base.end, calendar: calendar)
            guard (request.excludedPortions?.count ?? 0) <= 3660,
                  request.excludedPortions?.keys.allSatisfy({ ChinaHolidayCalendar.date($0) != nil && $0 >= first && $0 <= last }) ?? true else { throw invalid() }
            let ranges = [request.base] + request.segments
            guard request.segments.count <= 3660, Set(ranges.map(\.id)).count == ranges.count else { throw invalid() }
            for range in ranges {
                guard range.start.timeIntervalSince1970.isFinite, range.end.timeIntervalSince1970.isFinite,
                      calendar.startOfDay(for: range.start) <= calendar.startOfDay(for: range.end), range.end.timeIntervalSince(range.start) < 3660 * 86400,
                      (0 ..< 1440).contains(range.boundaryMinute), WorkPlan.dayKey(range.start, calendar: calendar) >= WorkPlan.dayKey(request.base.start, calendar: calendar),
                      WorkPlan.dayKey(range.end, calendar: calendar) <= WorkPlan.dayKey(request.base.end, calendar: calendar) else { throw invalid() }
            }
        }
    }
    static func materialize(_ requests: [LeaveRequest], plan: WorkPlan, calendar: Calendar) throws -> [String: LeaveDay] {
        try validate(requests, calendar: calendar)
        var result: [String: LeaveDay] = [:]
        for request in requests {
            var draft = LeaveRequestDraft(); draft.base = request.base; draft.changes = request.segments
            var days = try LeaveLedger.applying(draft, to: [:], plan: plan, calendar: calendar)
            for (key, portion) in request.excludedPortions ?? [:] {
                days[key]?.remove(portion)
                if days[key]?.isEmpty == true { days.removeValue(forKey: key) }
            }
            for (key, day) in days {
                var existing = result[key] ?? LeaveDay()
                guard !(existing.morning != nil && day.morning != nil), !(existing.afternoon != nil && day.afternoon != nil) else {
                    throw DayPerkInputError(message: L10n.format("leave.overlap", key))
                }
                guard existing.isEmpty || existing.boundaryMinute == day.boundaryMinute else {
                    throw DayPerkInputError(message: L10n.text("leave.boundary_mismatch"))
                }
                existing.morning = day.morning ?? existing.morning; existing.afternoon = day.afternoon ?? existing.afternoon
                if day.morning != nil { existing.morningKind = day.morningKind }
                if day.afternoon != nil { existing.afternoonKind = day.afternoonKind }
                existing.boundaryMinute = day.boundaryMinute; result[key] = existing
            }
        }
        return result
    }
    static func excluding(_ portions: [String: LeavePortion], from requests: [LeaveRequest], calendar: Calendar) -> [LeaveRequest] {
        requests.map { request in
            var value = request
            let first = WorkPlan.dayKey(request.base.start, calendar: calendar)
            let last = WorkPlan.dayKey(request.base.end, calendar: calendar)
            for (key, portion) in portions where key >= first && key <= last {
                var excluded = value.excludedPortions ?? [:]
                if let old = excluded[key], old != portion { excluded[key] = .full }
                else { excluded[key] = portion }
                value.excludedPortions = excluded
            }
            return value
        }
    }
    static func summary(_ request: LeaveRequest, plan: WorkPlan, calendar: Calendar) throws -> LeaveSummary {
        let days = try materialize([request], plan: plan, calendar: calendar)
        return days.values.reduce(into: LeaveSummary()) { total, day in
            total.paidDays += day.paidFraction; total.unpaidDays += day.unpaidFraction
        }
    }
    static func migrate(_ days: [String: LeaveDay], plan: WorkPlan, calendar: Calendar) -> [LeaveRequest] {
        LeaveLedger.periods(days, plan: plan, calendar: calendar).map { period in
            let value = period.value
            let portion: LeavePortion = value.morning == nil ? .afternoon : value.afternoon == nil ? .morning : .full
            let base = LeaveRange(start: period.start, end: period.end, portion: portion,
                pay: value.morning ?? value.afternoon ?? .paid, boundaryMinute: value.boundaryMinute ?? 720,
                kind: value.morning != nil ? value.morningKind : value.afternoonKind)
            let segments = value.morning != nil && value.afternoon != nil && (value.morning != value.afternoon || (value.morningKind ?? .general) != (value.afternoonKind ?? .general))
                ? [LeaveRange(start: period.start, end: period.end, portion: .morning, pay: value.morning!, boundaryMinute: base.boundaryMinute, kind: value.morningKind),
                   LeaveRange(start: period.start, end: period.end, portion: .afternoon, pay: value.afternoon!, boundaryMinute: base.boundaryMinute, kind: value.afternoonKind)] : []
            return LeaveRequest(base: base, segments: segments)
        }
    }
    private static func invalid() -> DayPerkInputError { DayPerkInputError(message: L10n.text("leave.invalid_range")) }
}

struct LeavePeriod: Identifiable {
    var start: Date
    var end: Date
    var value: LeaveDay
    var workdays = 1
    var id: Date { start }
}

enum LeaveLedger {
    static let storageKey = "dayperkLeaveDays"
    static func validate(_ days: [String: LeaveDay]) throws {
        guard days.count <= 36_600, days.allSatisfy({ key, day in
            ChinaHolidayCalendar.date(key) != nil && !day.isEmpty && (0 ..< 1440).contains(day.boundaryMinute ?? 720)
                && (day.morning != nil || day.morningKind == nil) && (day.afternoon != nil || day.afternoonKind == nil)
        }) else { throw DayPerkInputError(message: L10n.text("leave.invalid")) }
    }

    static func adding(_ ranges: [LeaveRange], to existing: [String: LeaveDay], plan: WorkPlan, calendar: Calendar, skipsRestOnlyRanges: Bool = false) throws -> [String: LeaveDay] {
        guard !ranges.isEmpty else { throw DayPerkInputError(message: L10n.text("leave.add_range")) }
        var result = existing
        for range in ranges {
            var cursor = calendar.startOfDay(for: range.start)
            let end = calendar.startOfDay(for: range.end)
            guard (0 ..< 1440).contains(range.boundaryMinute), cursor <= end, let length = calendar.dateComponents([.day], from: cursor, to: end).day,
                  length < 3660 else { throw DayPerkInputError(message: L10n.text("leave.invalid_range")) }
            var added = false
            while cursor <= end {
                let key = WorkPlan.dayKey(cursor, calendar: calendar)
                if plan.isScheduledWorkday(cursor, calendar: calendar) || plan.overtimeDates[key] != nil {
                    if range.portion != .full {
                        let shift = plan.schedule(for: key)
                        guard shift.offset(range.boundaryMinute) > 0, shift.offset(range.boundaryMinute) < shift.spanMinutes else {
                            throw DayPerkInputError(message: L10n.text("leave.invalid_boundary"))
                        }
                    }
                    var day = result[key] ?? LeaveDay()
                    guard !day.contains(range.portion) else { throw DayPerkInputError(message: L10n.format("leave.overlap", key)) }
                    if !day.isEmpty, range.portion != .full, (day.boundaryMinute ?? 720) != range.boundaryMinute {
                        throw DayPerkInputError(message: L10n.text("leave.boundary_mismatch"))
                    }
                    day.boundaryMinute = range.boundaryMinute
                    day.set(range.portion, pay: range.pay, kind: range.kind ?? .general); result[key] = day; added = true
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
                cursor = next
            }
            guard added || skipsRestOnlyRanges else { throw DayPerkInputError(message: L10n.text("leave.no_workdays")) }
        }
        try validate(result)
        return result
    }

    static func applying(_ draft: LeaveRequestDraft, to existing: [String: LeaveDay], plan: WorkPlan, calendar: Calendar) throws -> [String: LeaveDay] {
        let start = WorkPlan.dayKey(draft.base.start, calendar: calendar)
        let end = WorkPlan.dayKey(draft.base.end, calendar: calendar)
        let base = try adding([draft.base], to: [:], plan: plan, calendar: calendar, skipsRestOnlyRanges: true)
        var result = existing.filter { $0.key < start || $0.key > end }
        result.merge(base, uniquingKeysWith: { _, new in new })
        var adjusted = Set<String>()
        for range in draft.changes {
            guard WorkPlan.dayKey(range.start, calendar: calendar) >= start,
                  WorkPlan.dayKey(range.end, calendar: calendar) <= end else {
                throw DayPerkInputError(message: L10n.text("leave.change_outside"))
            }
            let changes = try adding([range], to: [:], plan: plan, calendar: calendar, skipsRestOnlyRanges: true)
            for (key, day) in changes {
                // 首次分段调整替换全天默认值；同日的后续半天调整可以分别设置薪资类型。
                if !adjusted.contains(key) || range.portion == .full { result[key] = day }
                else {
                    var current = result[key] ?? LeaveDay()
                    guard (current.boundaryMinute ?? 720) == range.boundaryMinute else {
                        throw DayPerkInputError(message: L10n.text("leave.boundary_mismatch"))
                    }
                    current.set(range.portion, pay: range.pay, kind: range.kind ?? .general); result[key] = current
                }
                adjusted.insert(key)
            }
        }
        try validate(result)
        return result
    }

    static func periods(_ days: [String: LeaveDay], plan: WorkPlan, calendar: Calendar) -> [LeavePeriod] {
        func date(_ key: String) -> Date? {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
        var result: [LeavePeriod] = []
        for key in days.keys.sorted() {
            guard let current = date(key), let value = days[key] else { continue }
            if let last = result.last, last.value == value {
                var cursor = calendar.date(byAdding: .day, value: 1, to: last.end) ?? current
                var continuous = true
                while cursor < current {
                    if plan.isScheduledWorkday(cursor, calendar: calendar) || plan.overtimeDates[WorkPlan.dayKey(cursor, calendar: calendar)] != nil {
                        continuous = false; break
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
                    cursor = next
                }
                if continuous { result[result.count - 1].end = current; result[result.count - 1].workdays += 1; continue }
            }
            result.append(LeavePeriod(start: current, end: current, value: value))
        }
        return result
    }
}

extension DayPerkModel {
    var leaveRequests: [LeaveRequest] {
        if let data = UserDataStore.shared.data(forKey: LeaveRequests.storageKey),
           let requests = try? JSONDecoder().decode([LeaveRequest].self, from: data), (try? LeaveRequests.validate(requests, calendar: workCalendar)) != nil { return requests }
        let migrated = LeaveRequests.migrate(leaveDays, plan: tracking.plan, calendar: workCalendar)
        if let data = try? JSONEncoder().encode(migrated) { UserDataStore.shared.set(data, forKey: LeaveRequests.storageKey) }
        return migrated
    }
    func saveLeaveRequest(_ draft: inout LeaveRequestDraft, addSegment: Bool = false, finish: Bool = false) throws {
        try draft.confirm(addSegment: addSegment, finish: finish) { request in
            var request = request
            let first = WorkPlan.dayKey(request.base.start, calendar: workCalendar)
            let last = WorkPlan.dayKey(request.base.end, calendar: workCalendar)
            request.excludedPortions = request.excludedPortions?.filter { $0.key >= first && $0.key <= last }
            let days = try LeaveRequests.materialize([request], plan: businessPlan, calendar: workCalendar)
            let portions = days.mapValues { day in day.morning == nil ? LeavePortion.afternoon : day.afternoon == nil ? .morning : .full }
            var requests = LeaveRequests.excluding(portions, from: leaveRequests.filter { $0.id != request.id }, calendar: workCalendar)
            requests.append(request)
            try saveLeaveRequests(requests)
        }
    }
    func saveLeaveRequests(_ requests: [LeaveRequest]) throws {
        let days = try LeaveRequests.materialize(requests, plan: businessPlan, calendar: workCalendar)
        var overrides = configuration.dateOverrides, overtime = overtimeDates
        for key in Set(leaveDays.keys).subtracting(days.keys) {
            overrides.removeValue(forKey: key); overtime.removeValue(forKey: key)
        }
        for key in days.keys where overtime[key] != nil {
            overtime.removeValue(forKey: key)
            overrides[key] = true
        }
        try saveCalendar(overrides: overrides, overtime: overtime, days: days, requests: requests,
                         changed: Set(leaveDays.keys).union(days.keys).filter { leaveDays[$0] != days[$0] })
    }

    func applyDayArrangement(_ kind: DayArrangement, on date: Date, multiplier: Double = 2) throws {
        let key = WorkPlan.dayKey(date, calendar: workCalendar)
        guard ChinaHolidayCalendar.date(key) != nil else { throw DayPerkInputError(message: L10n.text("leave.invalid")) }
        let existingMakeup = configuration.dateOverrides[key] == true && overtimeDates[key] == nil
        if kind == .makeup, !existingMakeup, !businessPlan.canMakeupWorkday(date, calendar: workCalendar) {
            throw DayPerkInputError(message: L10n.text("schedule.makeup_rest_only"))
        }
        if kind == .overtime, !OvertimeRateInput.isValid(multiplier) {
            throw DayPerkInputError(message: L10n.text("ui.overtime_multipliers_must_be_greate.c2b4b41e"))
        }
        var overrides = configuration.dateOverrides, overtime = overtimeDates, days = leaveDays
        overrides.removeValue(forKey: key); overtime.removeValue(forKey: key); days.removeValue(forKey: key)
        if kind == .makeup { overrides[key] = true }
        if kind == .rest { overrides[key] = false }
        if kind == .overtime { overtime[key] = multiplier }
        let requests = LeaveRequests.excluding([key: .full], from: leaveRequests, calendar: workCalendar)
        try saveCalendar(overrides: overrides, overtime: overtime, days: days, requests: requests, changed: [key])
    }


    func saveLeaveDays(_ days: [String: LeaveDay], preservingRequests: Bool = false) throws {
        try LeaveLedger.validate(days)
        if !preservingRequests { UserDataStore.shared.removeObject(forKey: LeaveRequests.storageKey) }
        let changed = Set(leaveDays.keys).union(days.keys).filter { leaveDays[$0] != days[$0] }
        guard !changed.isEmpty else { return }
        let data = try JSONEncoder().encode(days)
        UserDataStore.shared.set(data, forKey: LeaveLedger.storageKey)
        leaveDays = days
        refreshPayroll(leaveChangedDays: Set(changed))
    }

    func activeLeave(for key: String) -> LeaveDay? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = workCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              businessPlan.isScheduledWorkday(date, calendar: workCalendar) || overtimeDates[key] != nil else { return nil }
        return leaveDays[key]
    }

    func leaveSummary(for key: String) -> LeaveSummary {
        let day = activeLeave(for: key)
        guard let day else { return LeaveSummary() }
        let schedule = businessPlan.schedule(for: key)
        let first = Double(schedule.morningReferenceMinutes(boundary: day.boundaryMinute ?? 720) * 60)
        let last = Double(max(0, schedule.referenceMinutes * 60)) - first
        return LeaveSummary(paidSeconds: (day.morning == .paid ? first : 0) + (day.afternoon == .paid ? last : 0),
                unpaidSeconds: (day.morning == .unpaid ? first : 0) + (day.afternoon == .unpaid ? last : 0),
                paidDays: day.paidFraction, unpaidDays: day.unpaidFraction)
    }

    func unpaidLeaveDeductions(year: Int, monthlyGross: Double) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (key, _) in leaveDays where key.hasPrefix(String(year) + "-") {
            let month = Int(key.dropFirst(5).prefix(2)) ?? 0
            let days = workdays(year: year, month: month)
            if days > 0 { result[month, default: 0] += monthlyGross / Double(days) * (activeLeave(for: key)?.unpaidFraction ?? 0) }
        }
        return result.mapValues { PayrollCalculator.money(min(monthlyGross, $0)) }
    }
}
