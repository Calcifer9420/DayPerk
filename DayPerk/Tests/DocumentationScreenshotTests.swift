import AppKit
import CryptoKit
@testable import DayPerk
import SwiftUI
import Testing

/// 仅在独立文档应用中导出，所有金额来自本机忽略目录中的演示数据。
struct DocumentationScreenshotTests {
    @Test func documentationBackgroundIsPublicAndTestOnly() throws {
        let image = try Self.publicBackgroundURL()
        let digest = SHA256.hash(data: try Data(contentsOf: image)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "215a6eb66ebd3df20f37f07e843b6697059d99d805f9671a34a9fba267a6fe50")
        #expect(Bundle.main.url(forResource: "READMEBackground", withExtension: "png") == nil)
    }

    private static func publicBackgroundURL() throws -> URL {
        try #require(Bundle(for: DocumentationResourceAnchor.self).url(forResource: "READMEBackground", withExtension: "png"))
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportReadmeAppearanceScreenshots() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, appearanceOnly: true) }
    }

    @MainActor func exportReadmeDetails() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, readmeDetailsOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportDashboardShowcaseReview() throws {
        for language in AppLanguage.allCases where language != .system { try export(language: language, panelShowcaseOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportCurrentReview() throws {
        for language in [AppLanguage.chinese, .english] {
            try export(language: language)
            try export(language: language, motionOnly: true)
            try export(language: language, toastOnly: true)
        }
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, panelLayoutOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportReadmeScreenshots() throws {
        for language in [AppLanguage.chinese, .english] {
            try export(language: language)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportLanguageAndLayoutReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, languageReviewOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportScheduleRuleReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, scheduleRulesOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportGlobalSettingsReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, globalSettingsOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportTimeZoneScreenshots() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, timeZoneOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportCelebrationScreenshots() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, celebrationOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportFinalReviewScreenshots() throws {
        try export(language: .chinese, celebrationOnly: true)
        for language in [AppLanguage.chinese, .english] { try export(language: language, statisticsOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportStatisticsReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, statisticsOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportShowcaseReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, showcaseOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportHelpPositionReview() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, helpReviewOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportActivityAndDateReview() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, activityDateReviewOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportPanelBackgroundReview() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, backgroundReviewOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportLeaveReview() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, leaveReviewOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportReadmeMotion() throws {
        for language in [AppLanguage.chinese, .english] { try export(language: language, motionOnly: true) }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func panelHeightAndFooterStayPutAcrossClockOutAndResume() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, panelLayoutOnly: true)
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func pendingAuthenticationDoesNotGrowLockedPanel() throws {
        for language in AppLanguage.allCases where language != .system {
            try export(language: language, authenticationOnly: true)
        }
    }

    @MainActor private func export(language: AppLanguage, timeZoneOnly: Bool = false, celebrationOnly: Bool = false, statisticsOnly: Bool = false, backgroundReviewOnly: Bool = false, leaveReviewOnly: Bool = false, motionOnly: Bool = false, panelLayoutOnly: Bool = false, toastOnly: Bool = false, languageReviewOnly: Bool = false, scheduleRulesOnly: Bool = false, authenticationOnly: Bool = false, helpReviewOnly: Bool = false, activityDateReviewOnly: Bool = false, showcaseOnly: Bool = false, globalSettingsOnly: Bool = false, appearanceOnly: Bool = false, panelShowcaseOnly: Bool = false, readmeDetailsOnly: Bool = false) throws {
        try #require(Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true)
        // 每次导出使用独立应用标识，只写虚构数据，不清理或读取个人安装。
        var seed = try LocalPreviewMode.loadSeed()
        seed.monthlySalary = 114_514
        seed.policyID = [.chinese, .traditionalChinese].contains(language) ? nil : "us-san-jose"
        seed.language = language.rawValue
        try #require(seed.history.count >= 90)
        try #require(Set(seed.history.compactMap(\.overtimeMultiplier)).count >= 2)
        try LocalPreviewMode.prepare(seed)
        // 工作状态总量对应虚构工时，休息片段单独准备，只写文档沙盒。
        var statusSample = WorkStatusData()
        statusSample.selectedID = WorkStatusDefinition.rest.id
        let sampleCalendar = RegionalPayrollSettings().calendar
        for day in seed.history where day.hours > 0 {
            let date = try #require(sampleCalendar.date(byAdding: .day, value: day.dayOffset, to: Date()))
            var start = try #require(sampleCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: date))
            for (index, fraction) in [0.35, 0.2, 0.15, 0.1, 0.1, 0.1].enumerated() {
                let end = start.addingTimeInterval(day.hours * 3600 * fraction)
                statusSample.segments.append(WorkStatusSegment(statusID: statusSample.definitions[index].id, start: start, end: end))
                start = end
                if index == 1 {
                    let restEnd = start.addingTimeInterval(3600)
                    statusSample.segments.append(WorkStatusSegment(statusID: WorkStatusDefinition.rest.id, start: start, end: restEnd))
                    start = restEnd
                }
            }
        }
        try statusSample.validate()
        UserDataStore.shared.set(try JSONEncoder().encode(statusSample), forKey: WorkStatusController.storageKey)
        var delaysAuthentication = false
        var pendingAuthentication: ((Bool) -> Void)?
        let model = DayPerkModel(authenticate: { _, completion in
            if delaysAuthentication { pendingAuthentication = completion }
            else { completion(true) }
        })
        defer { model.tracking.shutdown() }
        try LocalPreviewMode.apply(seed, to: model)
        model.privacy.isStatisticsShowcaseEnabled = false
        model.access.unlockSettings()
        model.refreshHistoricalData()
        try #require(model.tracking.state.days.count >= 90)
        #expect(model.tracking.state.days.allSatisfy { (0 ... 86400).contains($0.seconds) })
        var config = model.configuration
        // 下班演示需要一个虚构工作日，不能因截图当天恰好放假而变成无偿加班。
        if !model.isWorkday {
            config.dateOverrides[model.today.id] = true
            try model.saveConfiguration(config)
        }
        let mainRegion = model.regional.region, mainInput = model.regional.input, mainPolicy = model.regional.selectedPolicy
        let mainTimeZone = model.regional.timeZoneID
        func restoreMainSample() throws {
            try model.saveRegionalSettings(region: mainRegion, input: mainInput, policy: mainPolicy, timeZoneID: mainTimeZone, benefit: WithdrawableBenefit())
            try model.saveConfiguration(config)
        }
        func useChinaSample() throws {
            try model.saveRegionalSettings(region: .china, input: RegionalPayInput(), policy: .custom, timeZoneID: "Asia/Shanghai", benefit: WithdrawableBenefit())
            var china = model.configuration; china.currency = .cny
            try model.saveConfiguration(china)
            let holiday = try #require(model.workCalendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
            #expect(!model.businessPlan.isScheduledWorkday(holiday, calendar: model.workCalendar))
        }
        try #require(config.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        try #require(!config.rhythm.enabled)
        if model.usesChinaPayroll {
            let imported = ChinaHolidayCalendar.merging(ChinaHolidayCalendar.bundledPlans(), into: [:], imported: [:]).overrides
            // 下班截图会把当天临时设为工作日，法定假日的其余日期仍须保留。
            #expect(config.dateOverrides.filter { $0.key != model.today.id } == imported.filter { $0.key != model.today.id })
        } else { #expect(config.dateOverrides.keys.allSatisfy { $0 == model.today.id }) }
        LocalizationManager.shared.setLanguage(language)
        model.appearance.select(.cyan)
        // 截图只使用仓库内的公开插画，连关闭背景时的缩略图也不能沿用私人图片。
        try model.appearance.importBackground(from: Self.publicBackgroundURL())
        var background = BackgroundPreferences(); background.enabled = false
        model.appearance.updateBackground(background)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPerkReadmeScreens-" + Bundle.main.bundleIdentifier! + "-" + language.rawValue)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var panelFrames: [String: CGRect] = [:]
        func writePNG(_ view: NSView, _ name: String) throws {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            if name == "history-window" {
                #expect(view.bounds.size == NSSize(width: 980, height: 1240))
                let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 40, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                #expect(color.greenComponent - color.redComponent > 0.02)
                #expect(color.blueComponent - color.redComponent > 0.02)
            }
            #expect(png.count > (name == "review-action-icons" ? 1000 : 5000))
            if name == "review-action-icons" {
                var redPixels = 0
                for y in 0 ..< bitmap.pixelsHigh {
                    for x in 0 ..< bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if color.redComponent > 0.6, color.redComponent > color.greenComponent * 1.5, color.redComponent > color.blueComponent * 1.5 { redPixels += 1 }
                    }
                }
                // 红色应来自图标，不能把整块按钮背景染红。
                #expect(redPixels > 8 && redPixels < bitmap.pixelsWide * bitmap.pixelsHigh / 40)
            }
            if name == "panel-background-tall" {
                #expect(abs(view.bounds.height - 720) < 1)
                for y in [5, bitmap.pixelsHigh - 6] {
                    let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.usingColorSpace(.deviceRGB))
                    #expect(color.alphaComponent > 0.98)
                    #expect(color.greenComponent - color.redComponent > 0.02)
                    #expect(color.blueComponent - color.redComponent > 0.02)
                }
            }
            try png.write(to: directory.appendingPathComponent(name + "-raw.png"))
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func capture<V: View>(_ view: V, _ name: String, _ size: NSSize, scroll: Double = 0, auditQuestions: Bool = false) throws {
            panelFrames = [:]
            model.endClockOutCelebration()
            let hosting = NSHostingView(rootView: view.environment(\.locale, LocalizationManager.shared.currentLocale)
                .environment(\.timeZone, model.workCalendar.timeZone)
                .overlayPreferenceValue(PanelAreaAnchors.self) { anchors in
                    GeometryReader { geometry in
                        let _ = { panelFrames = anchors.mapValues { geometry[$0] } }()
                        Color.clear.allowsHitTesting(false)
                    }
                })
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            if auditQuestions { window.identifier = NSUserInterfaceItemIdentifier(name.hasPrefix("help-dashboard") ? "DayPerk-dashboard" : "DayPerk-preferences") }
            defer { window.orderOut(nil); window.close() }
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = hosting; hosting.frame = NSRect(origin: .zero, size: size)
            // 让 SwiftUI 完成窗口绘制，透明且不接收鼠标，避免离屏缓存残留上一帧的文字。
            window.alphaValue = 0; window.ignoresMouseEvents = true; window.orderFront(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hosting.layoutSubtreeIfNeeded()
            let contentHeight = name == "leave-range-editor" ? panelFrames["leave-range"].map { $0.maxY + 22 } : panelFrames["panel-content"]?.height
            if name != "panel-background-tall", let height = contentHeight, height.isFinite, height >= 100 {
                let fitted = NSSize(width: size.width, height: ceil(height))
                window.setContentSize(fitted)
                hosting.frame = NSRect(origin: .zero, size: fitted)
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                hosting.layoutSubtreeIfNeeded()
                if panelFrames["panel-content"] != nil { #expect(abs(hosting.bounds.height - model.preferredPanelHeight) <= 1) }
            }
            if auditQuestions, let screen = window.screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: screen.midX - window.frame.width / 2, y: screen.midY - window.frame.height / 2))
            }
            if scroll > 0 {
                func findScroll(_ view: NSView) -> NSScrollView? {
                    if let value = view as? NSScrollView, let document = value.documentView,
                       document.frame.height > value.contentView.bounds.height + 20 { return value }
                    return view.subviews.lazy.compactMap { findScroll($0) }.first
                }
                let scroller = try #require(findScroll(hosting))
                let document = try #require(scroller.documentView)
                let distance = max(0, document.frame.height - scroller.contentView.bounds.height)
                scroller.contentView.scroll(to: NSPoint(x: 0, y: distance * scroll))
                scroller.reflectScrolledClipView(scroller.contentView)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                hosting.layoutSubtreeIfNeeded()
            }
            window.displayIfNeeded(); hosting.displayIfNeeded()
            if name.hasPrefix("dashboard-showcase") {
                let clockOut = try #require(panelFrames["clock-out"])
                let camera = try #require(panelFrames["showcase"])
                let quit = try #require(panelFrames["quit"])
                #expect(clockOut.maxX < camera.minX && camera.maxX < quit.minX)
                #expect(quit.maxX <= hosting.bounds.width - 20)
            }
            if ["statistics", "daily-statistics", "monthly-statistics"].contains(name) {
                for key in ["statistics-toolbar", "statistics-table"] {
                    let frame = try #require(panelFrames[key])
                    #expect(frame.minX >= 0 && frame.maxX <= hosting.bounds.width + 1)
                }
            }
            try writePNG(hosting, name)
            if auditQuestions {
                func scrollers(in view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollers(in: $0) }
                }
                let scroller = scrollers(in: hosting).filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 20 }
                    .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
                var checked = Set<String>()
                for _ in 0 ..< 20 {
                    for button in HelpPopoverTests.questions(in: hosting) where !button.isHiddenOrHasHiddenAncestor && button.visibleRect.contains(button.bounds) {
                        let key = String(describing: ObjectIdentifier(button)) + button.explanation
                        guard !checked.contains(key) else { continue }
                        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
                        guard window.screen?.visibleFrame.contains(frame) == true else { continue }
                        let point = hosting.superview?.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button) ?? .zero
                        let hit = hosting.hitTest(point)
                        guard hit === button || hit?.isDescendant(of: button) == true else { continue }
                        try autoreleasepool { try HelpPopoverTests.checkPosition(of: button, context: language.rawValue + "/" + name + "/" + button.explanation) }
                        checked.insert(key)
                    }
                    guard let scroller, let document = scroller.documentView else { break }
                    let current = scroller.contentView.bounds.minY
                    let next = min(max(0, document.frame.height - scroller.contentView.bounds.height), current + scroller.contentView.bounds.height * 0.8)
                    guard next > current + 1 else { break }
                    scroller.contentView.scroll(to: NSPoint(x: 0, y: next)); scroller.reflectScrolledClipView(scroller.contentView)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05)); hosting.layoutSubtreeIfNeeded()
                }
                print("help-position-audit: \(language.rawValue)/\(name): \(checked.count)")
                #expect(!checked.isEmpty)
            }
            window.contentView = nil
        }
        func captureHelp(_ button: HoverHelpButton, _ name: String) throws {
            button.explanation = L10n.text(button.explanation)
            button.options = button.options.map { HelpOption(title: L10n.text($0.title), isOn: $0.isOn, change: $0.change) }
            button.formula = button.formula?.map { var row = $0; row.amount = L10n.text(row.amount); row.label = row.resolvedLabel(translate: L10n.text); return row }
            if var hours = button.hours {
                hours.title = L10n.text(hours.title); hours.detail = L10n.text(hours.detail)
                hours.rows = hours.rows.map { HelpFormulaRow(amount: L10n.text($0.amount), label: L10n.text($0.label), isTotal: $0.isTotal) }
                button.hours = hours
            }
            let view = button.makeContent()
            view.appearance = NSAppearance(named: .darkAqua)
            view.wantsLayer = true; view.layer?.backgroundColor = model.appearance.theme.canvasNSColor.cgColor
            try writePNG(view, name)
        }
        if activityDateReviewOnly {
            model.workStatus.setEnabled(true)
            let actions = HStack(spacing: 12) {
                Button(role: .destructive) {} label: { Image(systemName: "trash") }
                Button {} label: { Image(systemName: "square.and.pencil") }
                Button {} label: { Image(systemName: "checkmark") }
                Button {} label: { Image(systemName: "xmark") }
            }.buttonStyle(BrewButtonStyle()).frame(width: 320, height: 80).background(model.appearance.theme.canvas)
            try capture(actions, "review-action-icons", NSSize(width: 320, height: 80))
            for page in [PreferencePage.workStatus, .history, .work] {
                try capture(DayPerkPreferencesView(model: model, initialPage: page), "review-" + page.id, NSSize(width: 980, height: 820))
            }
            if let record = model.payroll.records.first {
                try capture(PayrollRecordEditor(model: model, record: record), "review-history-editor", NSSize(width: 650, height: 650))
            }
            try capture(BrewDatePicker(title: "", selection: .constant(Date()), calendar: model.workCalendar).calendarPanel, "review-date-calendar", NSSize(width: 312, height: 365))
            try capture(BrewDatePicker(title: "", selection: .constant(Date()), calendar: model.workCalendar, monthsOnly: true).calendarPanel, "review-month-calendar", NSSize(width: 312, height: 270))
            return
        }
        if helpReviewOnly {
            model.access.unlockIncomeDetails()
            model.workStatus.setEnabled(true)
            try capture(DayPerkDashboardView(model: model) { _ in }, "help-dashboard", NSSize(width: 430, height: model.preferredPanelHeight), auditQuestions: true)
            for page in PreferencePage.allCases {
                try capture(DayPerkPreferencesView(model: model, initialPage: page), "help-" + page.id, NSSize(width: 980, height: 820), auditQuestions: true)
            }
            // 地区专属表单各检查一次，避免遗漏只在特定国家出现的说明。
            if language == .chinese {
                for region in PayrollRegion.allCases where region != .china {
                    let policy = PayrollCatalog.bundled.policies.first { $0.country == region } ?? .custom
                    var input = RegionalPayInput(); input.amount = 114_514
                    try model.saveRegionalSettings(region: region, input: input, policy: policy, timeZoneID: policy.timeZone, benefit: WithdrawableBenefit())
                    try capture(DayPerkPreferencesView(model: model, initialPage: .salary), "help-country-" + region.rawValue, NSSize(width: 980, height: 820), auditQuestions: true)
                }
            }
            return
        }
        if authenticationOnly {
            model.access.lockAllData()
            try capture(DayPerkDashboardView(model: model) { _ in }, "authentication-locked", NSSize(width: 430, height: 560))
            let height = model.preferredPanelHeight
            delaysAuthentication = true
            model.access.unlockAllData()
            #expect(model.access.isAuthenticating && !model.access.settingsUnlocked)
            try capture(DayPerkDashboardView(model: model) { _ in }, "authentication-pending", NSSize(width: 430, height: height))
            #expect(model.preferredPanelHeight == height)
            try capture(DayPerkPreferencesView(model: model, initialPage: .salary), "authentication-settings-pending", NSSize(width: 980, height: 820))
            let cancelAuthentication = try #require(pendingAuthentication)
            cancelAuthentication(false)
            #expect(!model.access.isAuthenticating && !model.access.settingsUnlocked && model.access.isDataLocked)
            try capture(DayPerkDashboardView(model: model) { _ in }, "authentication-canceled", NSSize(width: 430, height: height))
            #expect(model.preferredPanelHeight == height)
            model.access.unlockAllData()
            let grantAuthentication = try #require(pendingAuthentication)
            grantAuthentication(true)
            #expect(model.access.settingsUnlocked && !model.access.isDataLocked)
            try capture(DayPerkPreferencesView(model: model, initialPage: .salary), "authentication-settings-unlocked", NSSize(width: 980, height: 820))
            return
        }
        func captureTimeZonePicker() throws {
            try capture(VStack(spacing: 20) {
            WorkTimeZonePicker(identifier: .constant("Asia/Shanghai"), preferredCity: "Asia/Shanghai")
            WorkTimeZonePicker(identifier: .constant("GMT+0545"), preferredCity: "Asia/Shanghai")
        }.padding(20).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "time-zone-picker", NSSize(width: 650, height: 160))
        }
        func captureScheduleRules() throws {
            let fallback = DayWorkSchedule(startMinute: 540, endMinute: 1140, breakMinutes: 60)
            let early = DayWorkSchedule(startMinute: 540, endMinute: 1080, breakMinutes: 60)
            var rhythm = WorkRhythm(enabled: true, anchorDay: "2026-11-02")
            rhythm.cycleSchedules = [WorkRhythm.weekSlot(0, weekday: 6): early, WorkRhythm.weekSlot(1, weekday: 6): early]
            let friday = WorkScheduleRule(weekdays: [6], schedule: early)
            let wednesday = WorkScheduleRule(weekdays: [4], intervalWeeks: 2, anchorDay: "2026-11-02", schedule: early)
            rhythm.scheduleRules = [friday, wednesday]
            try capture(Form { WorkRhythmEditor(rhythm: .constant(rhythm), weekdays: .constant(config.weekdays), calendar: model.workCalendar, fallback: fallback) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "work-cycle", NSSize(width: 790, height: 410))
            try capture(Form { WorkScheduleRulesEditor(rhythm: .constant(rhythm), fallback: fallback, calendar: model.workCalendar, initiallyExpandedRuleID: wednesday.id) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "schedule-rules", NSSize(width: 790, height: 570))
        }
        if globalSettingsOnly {
            for page in [PreferencePage.workStatus, .work, .linking, .display, .salary, .statistics, .data] {
                try capture(DayPerkPreferencesView(model: model, initialPage: page), "global-unlocked-" + String(describing: page), NSSize(width: 980, height: 900))
            }
            try model.access.setAuthorizationDuration(3723)
            try capture(Form { Section(L10n.text("ui.pay_data_protection.2684cbc1")) { AuthorizationValidityView(access: model.access) } }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()),
                "global-authorization-timed", NSSize(width: 790, height: 250))
            try model.access.setAuthorizationDuration(0)
            try capture(Form { Section(L10n.text("ui.pay_data_protection.2684cbc1")) { AuthorizationValidityView(access: model.access) } }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()),
                "global-authorization-manual", NSSize(width: 790, height: 250))
            let weekly = WorkScheduleRule(weekdays: [6], schedule: DayWorkSchedule())
            var rhythm = WorkRhythm(); rhythm.scheduleRules = [weekly]
            try capture(Form { WorkScheduleRulesEditor(rhythm: .constant(rhythm), fallback: DayWorkSchedule(), calendar: model.workCalendar, initiallyExpandedRuleID: weekly.id) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "global-weekly-rule", NSSize(width: 790, height: 470))
            try useChinaSample()
            try model.saveBenefits([], region: .china, currency: "CNY")
            try capture(Form { WithdrawableBenefitsSection(model: model, region: .china, currency: "CNY") }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()),
                "global-add-benefit-menu", NSSize(width: 790, height: 200))
            var compensatory = LeaveRequestDraft(); compensatory.isSelecting = true
            let nextWorkday = try #require((0 ... 7).compactMap { model.workCalendar.date(byAdding: .day, value: $0, to: Date()) }
                .first { model.businessPlan.isScheduledWorkday($0, calendar: model.workCalendar) })
            compensatory.base = LeaveRange(start: nextWorkday, end: nextWorkday, kind: .compensatory)
            try capture(Form { LeaveEditorSections(model: model, draft: .constant(compensatory)) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "global-compensatory-leave", NSSize(width: 790, height: 420))
            model.access.revokeAuthorization()
            for page in [PreferencePage.workStatus, .salary, .data] {
                try capture(DayPerkPreferencesView(model: model, initialPage: page), "global-locked-" + String(describing: page), NSSize(width: 980, height: 900))
            }
            try model.access.setAuthorizationDuration(600)
            return
        }
        if scheduleRulesOnly {
            try captureScheduleRules()
            let early = DayWorkSchedule(startMinute: 540, endMinute: 1080, breakMinutes: 60)
            var daily = WorkRhythm(enabled: true, anchorDay: "2026-11-02", cycleDays: [true, true, true, true, true, false, false])
            daily.cycleSchedules = [WorkRhythm.daySlot(4): early]
            var dynamic = config
            dynamic.rhythm = daily
            try model.saveConfiguration(dynamic)
            #expect(model.tracking.plan.schedule(for: "2026-11-06") == early)
            #expect(model.configuration.referenceMinutes(for: "2026-11-06") == 480)
            #expect(model.access.sensitiveInformationWillHide != nil && model.access.dataWillLock != nil)
            #expect(model.monthlyReferenceSeconds(year: 2026, month: 11) == model.businessPlan.monthlyReferenceSeconds(year: 2026, month: 11, calendar: model.workCalendar))
            try capture(Form { WorkRhythmEditor(rhythm: .constant(daily), weekdays: .constant(config.weekdays), calendar: model.workCalendar, fallback: config.referenceSchedule, initiallyEditingCycleSlot: WorkRhythm.daySlot(4)) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "review-cycle-day-hours", NSSize(width: 790, height: 630))
            try model.saveConfiguration(config)
            try capture(Form { WorkLinkingView(config: .constant(config)).automationSections }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "automation-settings", NSSize(width: 790, height: 600))
            return
        }
        if languageReviewOnly {
            try capture(DayPerkPreferencesView(model: model, initialPage: .display), "review-language-appearance", NSSize(width: 980, height: 820))
            var nightRhythm = config.rhythm
            nightRhythm.daySchedules = ["2026-11-25": DayWorkSchedule(startMinute: 22 * 60, endMinute: 7 * 60,
                breakMode: .timeRanges, breaks: [WorkBreak(startMinute: 2 * 60, endMinute: 3 * 60)])]
            try capture(Form { DayScheduleEditor(rhythm: .constant(nightRhythm), day: "2026-11-25", fallback: config.referenceSchedule, calendar: model.workCalendar) }
                .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
                .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
                "review-date-schedule", NSSize(width: 790, height: 290))
            for id in ["hk-hong-kong", "mo-macau"] {
                let policy = try #require(PayrollCatalog.bundled.policies.first { $0.id == id })
                var input = RegionalPayInput(); input.amount = 114_514
                try model.saveRegionalSettings(region: policy.country, input: input, policy: policy, timeZoneID: policy.timeZone, benefit: WithdrawableBenefit())
                #expect(model.regionalEstimate != nil)
                try capture(DayPerkPreferencesView(model: model), "review-" + id, NSSize(width: 980, height: 820))
            }
            return
        }
        if toastOnly {
            ActionToastCenter.shared.show(L10n.text("ui.configuration_applied.e8381698"))
            defer { ActionToastCenter.shared.dismiss() }
            try capture(DayPerkPreferencesView(model: model), "settings-toast", NSSize(width: 980, height: 820))
            let toast = try #require(panelFrames["action-toast"])
            #expect(toast.minY >= 17 && toast.minY <= 20)
            return
        }
        if panelLayoutOnly {
            var initial: [String: CGRect] = [:]
            var initialHeight: CGFloat?
            func status() -> DashboardWorkStatus {
                DashboardWorkStatus(isWorking: model.tracking.state.isWorking, isSettled: model.isTodaySettled,
                    isRegisteredOvertime: model.isOvertime, exceededReference: model.hasExceededReferenceHours)
            }
            func check(_ name: String, _ expected: DashboardWorkStatus) throws {
                #expect(status() == expected)
                try capture(DayPerkDashboardView(model: model) { _ in }, name, NSSize(width: 430, height: model.preferredPanelHeight))
                #expect(status() == expected)
                let content = try #require(panelFrames["panel-content"])
                if let height = initialHeight {
                    #expect(abs(content.height - height) < 0.5)
                    for area in ["header", "work-controls", "daily-summary", "pay-summary", "footer"] {
                        let before = try #require(initial[area]), after = try #require(panelFrames[area])
                        #expect(abs(before.minY - after.minY) < 0.5, "\(language.rawValue) \(name) \(area)")
                        #expect(abs(before.height - after.height) < 0.5, "\(language.rawValue) \(name) \(area)")
                    }
                } else { initialHeight = content.height; initial = panelFrames }
                let footer = try #require(panelFrames["footer"])
                #expect(abs(content.height - footer.maxY - 22) < 1)
            }
            model.tracking.setWorking(true)
            try model.tracking.correctToday(seconds: 6 * 3600)
            try check("layout-working", .working)
            model.finishToday(); model.endClockOutCelebration()
            try check("layout-clocked-out-gain", .clockedOut)
            model.tracking.setWorking(true)
            try check("layout-resumed", .working)
            try model.tracking.correctToday(seconds: 10 * 3600)
            try check("layout-unpaid-overtime", .unpaidOvertime)
            model.tracking.setWorking(false)
            try check("layout-paused", .paused)
            model.finishToday(); model.endClockOutCelebration()
            #expect(model.settledBalance < 0)
            try check("layout-clocked-out-loss", .clockedOut)
            model.access.setSensitiveInformationHidden(true, privacy: model.privacy)
            try check("layout-hidden", .clockedOut)
            return
        }
        if readmeDetailsOnly {
            try capture(DayPerkPreferencesView(model: model, initialPage: .history), "history-window", NSSize(width: 980, height: 1240))
            model.tracking.setWorking(true)
            try capture(DayPerkDashboardView(model: model) { _ in }, "payday-before", NSSize(width: 430, height: model.preferredPanelHeight))
            return
        }
        if panelShowcaseOnly {
            model.privacy.isStatisticsShowcaseEnabled = true
            let original = model.today
            try capture(DayPerkDashboardView(model: model) { _ in }, "dashboard-showcase", NSSize(width: 430, height: model.preferredPanelHeight))
            #expect(model.today.seconds == original.seconds && model.today.earned == original.earned)
            let containsDigits = model.takeHomeEstimateFormula.contains { $0.isNumber }
            #expect(!containsDigits)
            model.finishToday()
            try capture(DayPerkDashboardView(model: model) { _ in }.overlay {
                Canvas { context, size in ClockOutConfetti.draw(in: context, size: size, elapsed: 1) }.allowsHitTesting(false)
            }.clipped(), "dashboard-showcase-celebration", NSSize(width: 430, height: model.preferredPanelHeight))
            try model.tracking.correctToday(seconds: 0)
            #expect(!WorkReportPresentation.canShareBalance(expectedIncome: model.expectedIncome(for: model.today), timeValue: model.today.earned))
            try capture(DayPerkDashboardView(model: model) { _ in }, "dashboard-showcase-protected", NSSize(width: 430, height: model.preferredPanelHeight))
            return
        }
        if appearanceOnly {
            try capture(DayPerkPreferencesView(model: model, initialPage: .display), "appearance", NSSize(width: 980, height: 800))
            background.enabled = true
            model.appearance.updateBackground(background)
            try capture(DayPerkDashboardView(model: model) { _ in }, "image-background", NSSize(width: 430, height: model.preferredPanelHeight))
            try capture(DayPerkPreferencesView(model: model, initialPage: .display), "image-background-settings", NSSize(width: 980, height: 800))
            return
        }
        if motionOnly {
            try capture(DayPerkDashboardView(model: model) { _ in }, "motion-before", NSSize(width: 430, height: model.preferredPanelHeight))
            let clock = DocumentationMotionClock()
            let size = NSSize(width: 430, height: model.preferredPanelHeight)
            let view = DocumentationClockoutMotion(model: model, clock: clock)
                .environment(\.locale, LocalizationManager.shared.currentLocale).environment(\.timeZone, model.workCalendar.timeZone)
                .overlayPreferenceValue(PanelAreaAnchors.self) { anchors in
                    GeometryReader { geometry in
                        let _ = {
                            panelFrames = anchors.mapValues { geometry[$0] }
                            if let anchor = anchors["clock-out"] { clock.buttonRect = geometry[anchor] }
                        }()
                        Color.clear.allowsHitTesting(false)
                    }
                }
            let hosting = NSHostingView(rootView: view); hosting.sizingOptions = []; hosting.safeAreaRegions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.orderOut(nil); window.close() }
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = hosting; hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            hosting.layoutSubtreeIfNeeded()
            let footer = try #require(panelFrames["footer"])
            let frames = directory.appendingPathComponent("motion-frames")
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            for index in 0 ..< 48 {
                if index == 8 { model.finishToday(); model.endClockOutCelebration() }
                clock.time = Double(index) / 16
                hosting.layoutSubtreeIfNeeded()
                #expect(abs(try #require(panelFrames["panel-content"]).height - size.height) < 1)
                #expect(abs(try #require(panelFrames["footer"]).minY - footer.minY) < 0.5)
                RunLoop.main.run(until: Date().addingTimeInterval(0.035))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: frames.appendingPathComponent(String(format: "%03d.png", index)))
            }
            #expect(model.isTodaySettled && model.settledBalance > 0)
            window.contentView = nil
            return
        }
        if leaveReviewOnly {
            var leaveConfig = model.configuration
            let calendar = model.workCalendar
            leaveConfig.startTime = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: Date())!
            leaveConfig.endTime = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: Date())!
            leaveConfig.breakMode = .timeRanges
            leaveConfig.breakPeriods = [WorkBreak(startMinute: 12 * 60, endMinute: 14 * 60)]
            try model.saveConfiguration(leaveConfig)
            let key = model.today.id
            let baseline = model.expectedIncome(for: model.today)
            let gross = model.breakdown.grossMonthlyIncome
            try model.saveLeaveDays([key: LeaveDay(morning: .unpaid)])
            #expect(abs(model.expectedIncome(for: model.today) - baseline / 2) < 0.02)
            #expect(model.tracking.plan.referenceSeconds(for: key) == 6.5 * 3600)
            #expect(model.breakdown.grossMonthlyIncome < gross)
            try model.tracking.correctToday(seconds: 6.5 * 3600)
            #expect(model.settledBalance < 0)
            try capture(LeaveManagementView(model: model).scrollContentBackground(.hidden).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color), "leave-management", NSSize(width: 980, height: 800))
            try capture(WorkStatisticsView(model: model, period: .week).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color), "leave-report", NSSize(width: 980, height: 850))
            try model.saveLeaveDays([key: LeaveDay(afternoon: .paid)])
            try model.tracking.correctToday(seconds: 90 * 60)
            #expect(model.tracking.plan.referenceSeconds(for: key) == 90 * 60)
            #expect(abs(model.expectedIncome(for: model.today) - baseline) < 0.02)
            #expect(model.settledBalance > 0)
            try capture(DayPerkDashboardView(model: model) { _ in }, "leave-paid-afternoon", NSSize(width: 430, height: 720))
            try model.saveLeaveDays([:])
            #expect(abs(model.breakdown.grossMonthlyIncome - gross) < 0.02)
            return
        }
        if backgroundReviewOnly {
            try capture(DayPerkDashboardView(model: model) { _ in }, "panel-background-tall", NSSize(width: 430, height: 720))
            try capture(DayPerkDashboardView(model: model) { _ in }, "dashboard", NSSize(width: 430, height: model.preferredPanelHeight))
            let detailsHeight = model.preferredPanelHeight
            #expect(detailsHeight < 620)
            model.finishToday()
            try capture(DayPerkDashboardView(model: model) { _ in }, "compact-settled", NSSize(width: 430, height: 720))
            #expect(model.preferredPanelHeight == detailsHeight)
            model.access.lockAllData()
            try capture(DayPerkDashboardView(model: model) { _ in }, "compact-locked", NSSize(width: 430, height: 560))
            #expect(model.preferredPanelHeight < 450)
            model.access.unlockAllData()
            try capture(DayPerkDashboardView(model: model) { _ in }, "compact-restored", NSSize(width: 430, height: 720))
            try capture(DayPerkPreferencesView(model: model, initialPage: .today), "today-correction", NSSize(width: 980, height: 1240))
            return
        }
        if showcaseOnly {
            let recorded = model.tracking.state.days
            model.workStatus.setEnabled(true)
            model.privacy.isStatisticsShowcaseEnabled = true
            for period in WorkReportPeriod.allCases {
                try capture(WorkStatisticsView(model: model, period: period).background(model.appearance.theme.canvas)
                    .preferredColorScheme(.dark).tint(model.appearance.theme.color),
                    "showcase-" + period.rawValue, NSSize(width: 980, height: 760))
            }
            try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics-showcase", NSSize(width: 980, height: 800))
            try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics-showcase-activities", NSSize(width: 980, height: 800), scroll: 1)
            model.access.revokeAuthorization()
            #expect(!model.access.settingsUnlocked)
            try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics-showcase-locked", NSSize(width: 980, height: 800))
            model.privacy.isStatisticsShowcaseEnabled = false
            try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics-locked", NSSize(width: 980, height: 800))
            model.access.unlockSettings()
            try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics", NSSize(width: 980, height: 800))
            #expect(model.tracking.state.days == recorded)
            return
        }
        if statisticsOnly {
        try capture(WorkStatisticsView(model: model, period: .day).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "daily-statistics", NSSize(width: 980, height: 600))
        try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics", NSSize(width: 980, height: 800))
        try capture(WorkStatisticsView(model: model, period: .month).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "monthly-statistics", NSSize(width: 980, height: 800))
        model.workStatus.setEnabled(true)
        try capture(DayPerkPreferencesView(model: model, initialPage: .workStatus), "work-status-settings", NSSize(width: 980, height: 820))
        // 使用已结束的演示记录，避免启用状态记录后选到当天的空白时段。
        let statusDay = try #require(statusSample.segments.last?.start)
        let interval = WorkStatusReport.interval(containing: statusDay, period: .day, calendar: model.workCalendar, dayStartMinute: model.configuration.dayStartMinute)
        #expect(!WorkStatusReport.totals(statusSample.segments, definitions: statusSample.definitions, interval: interval).isEmpty)
        try capture(WorkStatusStatisticsView(controller: model.workStatus, interval: interval, plan: model.businessPlan, days: model.reportRecords, calendar: model.workCalendar, day: statusDay)
            .padding(20).background(model.appearance.theme.canvas).preferredColorScheme(.dark),
            "work-status-report", NSSize(width: 790, height: 480))
        if let timeline = WorkStatusTimeline.make(segments: model.workStatus.recordedSegments(), days: model.reportRecords,
            plan: model.businessPlan, interval: interval, calendar: model.workCalendar, now: Date()) {
            try capture(WorkStatusTimelineView(timeline: timeline, definitions: model.workStatus.data.definitions,
                calendar: model.workCalendar, hoveredStatus: .constant("focus"), hoveredSegment: .constant(nil))
                .padding(18).background(model.appearance.theme.surface).preferredColorScheme(.dark),
                "timeline-highlight", NSSize(width: 790, height: 140))
        }
        try ReportChartExport.data(controller: model.workStatus, interval: interval, plan: model.businessPlan, days: model.reportRecords, locale: LocalizationManager.shared.currentLocale, calendar: model.workCalendar, day: statusDay).write(to: directory.appendingPathComponent("exported-chart.png"), options: .atomic)
        for period in [WorkReportPeriod.week, .month] {
            let report = WorkReport.make(days: model.reportRecords, containing: Date(), period: period, calendar: model.workCalendar,
                asOf: WorkStatisticsView.currentBusinessDate(model: model), expectedIncome: { model.expectedIncome(for: $0) },
                expectedWorkSeconds: { model.expectedWorkSeconds(for: $0) }, leave: { model.leaveSummary(for: $0) })
            try ReportExcelExport.data(report: report, currency: model.activeCurrencyCode, calendar: model.workCalendar, locale: LocalizationManager.shared.currentLocale).write(to: directory.appendingPathComponent("exported-" + period.rawValue + ".xlsx"), options: .atomic)
        }
            return
        }
        if celebrationOnly {
            let began = ProcessInfo.processInfo.systemUptime
            model.finishToday()
            let milliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
            print("clockout-ms: \(milliseconds)")
            #expect(milliseconds < 500)
            #expect(model.settledBalance > 0)
            for (elapsed, name) in [(0.7, "celebration-burst"), (1.0, "celebration-hero"), (1.7, "celebration-rain"), (3.3, "celebration-fall")] {
                try capture(DayPerkDashboardView(model: model) { _ in }.overlay {
                    Canvas { context, size in ClockOutConfetti.draw(in: context, size: size, elapsed: elapsed) }
                        .allowsHitTesting(false)
                }.clipped(), name, NSSize(width: 430, height: model.preferredPanelHeight))
            }
            return
        }
        if timeZoneOnly { try captureTimeZonePicker(); return }
        try capture(DayPerkDashboardView(model: model) { _ in }, "dashboard", NSSize(width: 430, height: model.preferredPanelHeight))
        let settlementBegan = ProcessInfo.processInfo.systemUptime
        model.finishToday()
        let settlementMS = (ProcessInfo.processInfo.systemUptime - settlementBegan) * 1000
        print("clockout-ms[\(language.rawValue)]: \(settlementMS)")
        #expect(settlementMS < 500)
        #expect(model.isTodaySettled && model.settledBalance > 0)
        try capture(DayPerkDashboardView(model: model) { _ in }, "early-clockout", NSSize(width: 430, height: model.preferredPanelHeight))
        do {
            try capture(DayPerkDashboardView(model: model) { _ in }.overlay {
                Canvas { context, size in ClockOutConfetti.draw(in: context, size: size, elapsed: 1.0) }.allowsHitTesting(false)
            }.clipped(), "celebration-hero", NSSize(width: 430, height: model.preferredPanelHeight))
        }
        try model.tracking.correctToday(seconds: 10 * 3600)
        model.finishToday()
        #expect(model.isTodaySettled && model.today.unpaidOvertimeSeconds > 0 && model.settledBalance < 0)
        try capture(DayPerkDashboardView(model: model) { _ in }, "early-clockout-loss", NSSize(width: 430, height: model.preferredPanelHeight))
        model.tracking.setWorking(true); model.tracking.setWorking(false)
        var largeIncome = config
        largeIncome.baseSalary = 999_999_999
        largeIncome.payroll.annualBonusBase = 999_999_999
        try model.saveConfiguration(largeIncome)
        try model.tracking.correctToday(seconds: 23 * 3600)
        try capture(DayPerkDashboardView(model: model) { _ in }, "large-amount", NSSize(width: 430, height: model.preferredPanelHeight))
        try model.saveConfiguration(config)
        model.tracking.setWorking(true); model.tracking.setWorking(false)
        var overtimeDemo = config
        overtimeDemo.overtimeDates[model.today.id] = 2
        try model.saveConfiguration(overtimeDemo)
        try model.tracking.correctToday(seconds: 9 * 3600)
        #expect(!model.isTodaySettled && model.today.unpaidOvertimeSeconds == 3600)
        #expect(model.breakdown.overtimeGross > 0)
        #expect(abs(model.settledBalance + model.minuteRate * 60) < 0.02)
        try capture(DayPerkDashboardView(model: model) { _ in }, "overtime-summary", NSSize(width: 430, height: model.preferredPanelHeight))
        try model.saveConfiguration(config)
        try model.tracking.correctToday(seconds: 7200)
        try useChinaSample()
        let rate = HoverHelpButton()
        rate.explanation = model.rateExplanation
        rate.options = [HelpOption(title: L10n.text("ui.include_annual_bonus.e30ae43d"), isOn: true) { _ in },
                        HelpOption(title: L10n.format("benefits.include_item", L10n.text("ui.housing_fund.397c8572")), isOn: true) { _ in },
                        HelpOption(title: L10n.text("ui.deduct_tax_employee_contributions.176b107c"), isOn: true) { _ in }]
        rate.hours = model.workHoursExplanation
        try captureHelp(rate, "rate-options")
        let hours = HoverHelpButton()
        hours.formula = model.workHoursExplanation.rows; hours.formulaTitle = L10n.text("ui.reference_work_hours.e292f271")
        hours.formulaFooter = L10n.text("ui.from_saved_settings_actual_time_fol.a72ee8fd")
        try captureHelp(hours, "hours-formula")
        let timeZone = HoverHelpButton()
        timeZone.explanation = WorkTimeZoneOptions.explanation
        try captureHelp(timeZone, "time-zone-help")
        try captureTimeZonePicker()
        let salary = HoverHelpButton()
        salary.formula = model.salaryFormulaRows
        salary.options = model.withdrawableBenefits.map { HelpOption(title: L10n.format("benefits.show_item", $0.displayName), isOn: $0.showInEstimate) { _ in } }
        try captureHelp(salary, "salary-breakdown")
        try capture(DayPerkPreferencesView(model: model, initialPage: .salary), "payroll", NSSize(width: 980, height: 740))
        try capture(Form { DayPerkPreferencesView(model: model).paydaySection }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "payday-settings", NSSize(width: 790, height: 280))
        try restoreMainSample()
        try capture(DayPerkPreferencesView(model: model, initialPage: .work), "work-settings", NSSize(width: 980, height: 800))
        var leaveDraft = LeaveRequestDraft()
        leaveDraft.beginSelection()
        let leaveStart = try #require(model.workCalendar.date(byAdding: .day, value: 7, to: Date()))
        let leaveEnd = try #require(model.workCalendar.date(byAdding: .day, value: 36, to: Date()))
        leaveDraft.base = LeaveRange(start: leaveStart, end: leaveEnd, kind: .compensatory)
        try model.saveLeaveRequest(&leaveDraft, addSegment: true)
        leaveDraft.selection.start = model.workCalendar.date(byAdding: .day, value: 4, to: leaveStart)!
        leaveDraft.selection.end = model.workCalendar.date(byAdding: .day, value: 8, to: leaveStart)!
        leaveDraft.selection.portion = .morning; leaveDraft.selection.pay = .unpaid
        leaveDraft.selection.kind = nil
        try model.saveLeaveRequest(&leaveDraft)
        try capture(HolidayCalendarView(overrides: .constant(config.dateOverrides), selectedDate: .constant(leaveDraft.selection.start),
            region: model.regional.region, subdivision: model.regional.selectedPolicy.subdivision, workCalendar: model.workCalendar,
            leaveDays: model.leaveDays, selectionEnd: .constant(leaveDraft.selection.end), confirmedRange: leaveStart ... leaveEnd,
            selectionBounds: leaveDraft.selectionBounds, selectionID: leaveDraft.selectedSegmentID)
            .padding(24).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "leave-calendar", NSSize(width: 790, height: 500))
        try capture(Form { LeaveEditorSections(model: model, draft: .constant(leaveDraft)) }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "leave-range-editor", NSSize(width: 790, height: 640))
        try model.saveLeaveDays([:])
        try capture(DataTransferView(model: model).background(model.appearance.theme.canvas).preferredColorScheme(.dark)
            .buttonStyle(BrewButtonStyle()).tint(model.appearance.theme.color), "data-backup", NSSize(width: 790, height: 370))
        model.workStatus.setEnabled(true)
        try capture(DayPerkPreferencesView(model: model, initialPage: .workStatus), "work-status-settings", NSSize(width: 980, height: 820))
        try capture(DayPerkDashboardView(model: model) { _ in }, "work-status-panel", NSSize(width: 430, height: model.preferredPanelHeight))
        let statusDay = try #require(statusSample.segments.last?.start)
        let statusInterval = WorkStatusReport.interval(containing: statusDay, period: .day, calendar: model.workCalendar, dayStartMinute: model.configuration.dayStartMinute)
        #expect(!WorkStatusReport.totals(statusSample.segments, definitions: statusSample.definitions, interval: statusInterval).isEmpty)
        try ReportChartExport.data(controller: model.workStatus, interval: statusInterval, plan: model.businessPlan, days: model.reportRecords, locale: LocalizationManager.shared.currentLocale, calendar: model.workCalendar, day: statusDay).write(to: directory.appendingPathComponent("exported-chart.png"), options: .atomic)
        for period in [WorkReportPeriod.week, .month] {
            let report = WorkReport.make(days: model.reportRecords, containing: Date(), period: period, calendar: model.workCalendar,
                asOf: WorkStatisticsView.currentBusinessDate(model: model), expectedIncome: { model.expectedIncome(for: $0) },
                expectedWorkSeconds: { model.expectedWorkSeconds(for: $0) }, leave: { model.leaveSummary(for: $0) })
            try ReportExcelExport.data(report: report, currency: model.activeCurrencyCode, calendar: model.workCalendar, locale: LocalizationManager.shared.currentLocale).write(to: directory.appendingPathComponent("exported-" + period.rawValue + ".xlsx"), options: .atomic)
        }
        try capture(WorkStatusStatisticsView(controller: model.workStatus, interval: statusInterval, plan: model.businessPlan, days: model.reportRecords, calendar: model.workCalendar, day: statusDay)
            .padding(20).background(model.appearance.theme.canvas).preferredColorScheme(.dark),
            "work-status-report", NSSize(width: 790, height: 480))
        model.workStatus.setEnabled(false)
        try capture(Form { WorkLinkingView(config: .constant(model.configuration)).automationSections }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color)
            .buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "automation-settings", NSSize(width: 790, height: 600))
        try captureScheduleRules()
        let calendarDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        try capture(HolidayCalendarView(overrides: .constant(config.dateOverrides), selectedDate: .constant(calendarDate), overtimeDates: ["2026-10-17": 2.5, "2026-10-18": 3], rhythm: WorkRhythm(enabled: true, anchorDay: "2026-10-05"))
            .padding(24).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "calendar", NSSize(width: 730, height: 420))
        try capture(DayPerkPreferencesView(model: model, initialPage: .today), "today-correction", NSSize(width: 980, height: 1240))
        try capture(DayPerkPreferencesView(model: model, initialPage: .history), "history-window", NSSize(width: 980, height: 1240))
        try capture(WorkStatisticsView(model: model, period: .day).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "daily-statistics", NSSize(width: 980, height: 600))
        try capture(DayPerkPreferencesView(model: model, initialPage: .statistics), "statistics", NSSize(width: 980, height: 800))
        try capture(WorkStatisticsView(model: model, period: .month).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "monthly-statistics", NSSize(width: 980, height: 800))
        try capture(DayPerkPreferencesView(model: model, initialPage: .display), "appearance", NSSize(width: 980, height: 800))
        try capture(Form { DayPerkPreferencesView(model: model).displayPrivacySections }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "display-privacy", NSSize(width: 790, height: 440))
        var foreignInput = RegionalPayInput()
        foreignInput.amount = seed.monthlySalary; foreignInput.frequency = .monthly
        let singapore = try #require(PayrollCatalog.bundled.policies(for: .singapore).first)
        try model.saveRegionalSettings(region: .singapore, input: foreignInput, policy: singapore, timeZoneID: "Asia/Singapore", benefit: WithdrawableBenefit(name: L10n.text("Flexible savings withdrawal"), monthlyAmount: 1234.56))
        try capture(RegionalPayrollView(model: model).background(model.appearance.theme.canvas).preferredColorScheme(.dark).tint(model.appearance.theme.color),
            "regional-payroll", NSSize(width: 790, height: 800))
        try capture(DayPerkDashboardView(model: model) { _ in }, "regional-dashboard", NSSize(width: 430, height: model.preferredPanelHeight))
        var extras = model.withdrawableBenefits
        extras.append(WithdrawableBenefit(name: L10n.text("benefits.demo_item"), monthlyAmount: 320, includeInRate: false))
        try model.saveBenefits(extras, region: .singapore, currency: singapore.currency)
        try capture(Form { RegionalPayrollView(model: model).withdrawableBenefitSection }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "regional-benefit-settings", NSSize(width: 790, height: 290))
        // 各地区使用相同的虚构基本月工资，税费按各自方案分别计算。
        LocalizationManager.shared.setLanguage(.chinese)
        try useChinaSample()
        try capture(DayPerkPreferencesView(model: model), "case-mainland-china", NSSize(width: 980, height: 820))
        for (policyID, name) in [("us-san-jose", "case-california"), ("sg-singapore", "case-singapore"), ("kr-seoul", "case-seoul"), ("jp-nagoya", "case-japan"), ("au-sydney", "case-australia"), ("ca-vancouver", "case-canada"), ("hk-hong-kong", "case-hong-kong"), ("mo-macau", "case-macau"), ("nz-auckland", "case-new-zealand"), ("de-berlin", "case-germany"), ("fr-paris", "case-france"), ("ca-montreal", "case-quebec")] {
            var selected = try #require(PayrollCatalog.bundled.policies.first { $0.id == policyID })
            let localLanguage: AppLanguage
            switch selected.country {
            case .japan: localLanguage = .japanese
            case .southKorea: localLanguage = .korean
            case .hongKong, .macau: localLanguage = .traditionalChinese
            case .germany: localLanguage = .german
            case .france: localLanguage = .french
            default: localLanguage = policyID == "ca-montreal" ? .french : .english
            }
            LocalizationManager.shared.setLanguage(localLanguage)
            var person = RegionalPayInput(); person.amount = 114_514; person.frequency = .monthly
            if selected.effectiveEmploymentKind == .domesticWorker { person.cpfStatus = "foreigner" }
            if selected.effectiveEmploymentKind == .selfEmployed {
                selected.contributions[0].employeeMonthlyAmount = 500
                selected.contributions[1].employeeMonthlyAmount = 300
                person.declaredContributionsConfirmed = true
            }
            if selected.country == .japan { person.age = 45; person.declaredMonthlySocialBase = 114_514; person.previousYearGrossIncome = 114_514 * 12 }
            try model.saveRegionalSettings(region: selected.country, input: person, policy: selected, timeZoneID: selected.timeZone, benefit: WithdrawableBenefit())
            try model.saveBenefits([], region: selected.country, currency: selected.currency)
            try capture(DayPerkPreferencesView(model: model), name, NSSize(width: 980, height: 820))
        }
        LocalizationManager.shared.setLanguage(language)
        try restoreMainSample()
        var nightRhythm = config.rhythm
        nightRhythm.daySchedules = ["2026-11-25": DayWorkSchedule(startMinute: 22 * 60, endMinute: 7 * 60, breakMode: .timeRanges, breaks: [WorkBreak(startMinute: 2 * 60, endMinute: 3 * 60)])]
        try capture(Form { DayScheduleEditor(rhythm: .constant(nightRhythm), day: "2026-11-25", fallback: config.referenceSchedule, calendar: model.workCalendar) }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color).buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "date-schedule", NSSize(width: 790, height: 290))
        try useChinaSample()
        // 专用文档应用使用虚构入职日期，仅渲染奖金区，不修改个人安装。
        var bonusDemo = model.configuration
        bonusDemo.payroll.prorateAnnualBonus = true
        bonusDemo.payroll.annualBonusStartDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!
        try model.saveConfiguration(bonusDemo)
        try capture(Form { DayPerkPreferencesView(model: model).annualBonusSection }
            .formStyle(.grouped).scrollContentBackground(.hidden).background(model.appearance.theme.canvas)
            .preferredColorScheme(.dark).tint(model.appearance.theme.color)
            .buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle()),
            "annual-bonus", NSSize(width: 760, height: 650))
        try restoreMainSample()
        try model.appearance.importBackground(from: Self.publicBackgroundURL())
        try capture(BackgroundCropEditor(appearance: model.appearance), "background-crop-settings", NSSize(width: 650, height: 610))
        try capture(BackgroundCropEditor(appearance: model.appearance, panel: true), "background-crop-panel", NSSize(width: 650, height: 610))
        try capture(DayPerkDashboardView(model: model) { _ in }, "image-background", NSSize(width: 430, height: model.preferredPanelHeight))
        try capture(DayPerkPreferencesView(model: model, initialPage: .display), "image-background-settings", NSSize(width: 980, height: 800))
        var restore = model.appearance.background; restore.enabled = false
        model.appearance.updateBackground(restore)
        // 用文档应用的虚构薪酬，在当天下班前半小时演算标绿，不改系统时间。
        var surplusDemo = config
        surplusDemo.dateOverrides[model.today.id] = true
        try model.saveConfiguration(surplusDemo)
        let day = model.tracking.plan.businessDayStart(for: Date(), calendar: model.workCalendar)
        let departure = try #require(model.workCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        try model.tracking.correctToday(seconds: 6 * 3600, at: departure.addingTimeInterval(-1800))
        try #require(model.hasSecuredDepartureSurplus)
        try capture(DayPerkDashboardView(model: model) { _ in }, "departure-surplus", NSSize(width: 430, height: model.preferredPanelHeight))
        model.access.setSensitiveInformationHidden(true, privacy: model.privacy)
        try capture(DayPerkDashboardView(model: model) { _ in }, "sensitive-mask", NSSize(width: 430, height: model.preferredPanelHeight))
        model.access.lockAllData()
        try capture(DayPerkDashboardView(model: model) { _ in }, "locked", NSSize(width: 430, height: model.preferredPanelHeight))
    }
}

private final class DocumentationResourceAnchor: NSObject {}

@MainActor private final class DocumentationMotionClock: ObservableObject {
    @Published var time = 0.0
    var buttonRect = CGRect.zero
}

private struct DocumentationClockoutMotion: View {
    @ObservedObject var model: DayPerkModel
    @ObservedObject var clock: DocumentationMotionClock
    var body: some View {
        DayPerkDashboardView(model: model) { _ in }
            .overlay {
                Canvas { context, size in
                    if clock.time >= 0.5 { ClockOutConfetti.draw(in: context, size: size, elapsed: clock.time - 0.5) }
                }.allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if clock.time >= 0.18 && clock.time < 0.85 {
                    Image(systemName: "cursorarrow").font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                        .shadow(color: .black, radius: 1).scaleEffect(clock.time >= 0.44 && clock.time < 0.62 ? 0.82 : 1)
                        .offset(x: clock.buttonRect.midX - 4, y: clock.buttonRect.midY - 3).allowsHitTesting(false)
                }
            }.clipped()
    }
}
