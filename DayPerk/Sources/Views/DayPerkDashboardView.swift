import SwiftUI

struct HelpOption {
    var title: String
    var isOn: Bool
    var change: (Bool) -> Void
}

/// 文档标注读取真实布局边界，不按语言或金额长度猜位置。
struct PanelAreaAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

enum RuleHelpText {
    static func bulleted(_ text: String) -> String {
        guard !text.contains("÷"), !text.contains("• ") else { return text }
        let separator = text.contains("。") ? "。" : ". "
        let items = text.components(separatedBy: "\n").flatMap { $0.components(separatedBy: separator) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return items.count > 1 ? items.map { "• " + $0 }.joined(separator: "\n\n") : text
    }
}

struct InfoHelp: NSViewRepresentable {
    @ObservedObject private var language = LocalizationManager.shared
    let text: String
    var formula: [HelpFormulaRow]? = nil
    var options: [HelpOption] = []
    var hours: WorkHoursExplanation? = nil
    var preferredEdge: NSRectEdge? = nil
    var access: SalaryAccessController? = nil
    func makeNSView(context _: Context) -> HoverHelpButton {
        HoverHelpButton()
    }

    func updateNSView(_ button: HoverHelpButton, context _: Context) {
        button.access = access
        button.explanation = L10n.text(text)
        button.formula = formula?.map { var row = $0; row.label = row.resolvedLabel(translate: L10n.text); return row }
        button.options = options.map { HelpOption(title: L10n.text($0.title), isOn: $0.isOn, change: $0.change) }
        button.hours = hours.map { WorkHoursExplanation(title: L10n.text($0.title), detail: L10n.text($0.detail), rows: $0.rows.map { HelpFormulaRow(amount: L10n.text($0.amount), label: L10n.text($0.label), isTotal: $0.isTotal) }) }
        button.preferredEdge = preferredEdge
        button.setAccessibilityLabel(access?.canViewIncomeDetails == false ? L10n.text("ui.unlock_income_breakdown.aedc0dfa") : L10n.text(text))
        button.refreshIfVisible()
    }
}

private final class HelpContainer: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area {
            removeTrackingArea(area)
        }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next); area = next
    }

    override func mouseEntered(with _: NSEvent) {
        entered?()
    }

    override func mouseExited(with _: NSEvent) {
        exited?()
    }
}

/// 原生悬浮与点击入口；交互面板允许移入勾选，点击外部关闭。
final class HoverHelpButton: NSButton {
    private weak static var activeHelp: HoverHelpButton?
    var explanation = ""
    var formula: [HelpFormulaRow]?
    var formulaTitle = "ui.monthly_take_home_estimate.9787e060"
    var formulaFooter = "ui.after_tax_and_employee_contribution.34397ee8"
    var options: [HelpOption] = []
    var hours: WorkHoursExplanation?
    var preferredEdge: NSRectEdge?
    weak var access: SalaryAccessController?
    private weak var parentHelp: HoverHelpButton?
    private weak var childHelp: HoverHelpButton?
    private var tracking: NSTrackingArea?
    private var helpPopover: NSPopover?
    private var localClicks: Any?
    private var globalClicks: Any?
    private var deactivate: NSObjectProtocol?
    private var pendingClose: DispatchWorkItem?
    private var rendered = ""

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        imagePosition = .imageOnly; isBordered = false; contentTintColor = .secondaryLabelColor
        target = self; action = #selector(showExplanation); setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError(L10n.text("ui.cannot_create_the_help_button_from.a3f3680b"))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }

    override func mouseEntered(with _: NSEvent) {
        pendingClose?.cancel(); showExplanation()
    }

    override func mouseExited(with _: NSEvent) {
        scheduleClose()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            closeExplanation()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private var fingerprint: String {
        AppearanceSettings.shared.theme.rawValue + String(access?.canViewIncomeDetails ?? true) + String(access?.settingsUnlocked ?? false) + String(access?.isAuthenticating ?? false) + explanation + (hours?.title ?? "") + (hours?.detail ?? "") + (formula ?? []).map { $0.amount + $0.label }.joined() + options.map { $0.title + String($0.isOn) }.joined()
    }

    @objc private func showExplanation() {
        guard let window, let host = window.contentView else { return }
        pendingClose?.cancel()
        guard helpPopover?.isShown != true else { return }
        if let parentHelp {
            parentHelp.childHelp?.closeExplanation()
            parentHelp.childHelp = self
        } else {
            Self.activeHelp?.rootHelp.closeExplanation()
        }
        Self.activeHelp = self
        let content = makeContent()
        let targetSize = content.frame.size
        let controller = NSViewController(); controller.view = content
        controller.preferredContentSize = targetSize
        let popup = NSPopover(); popup.behavior = .applicationDefined; popup.animates = false
        popup.appearance = NSAppearance(named: .darkAqua); popup.contentViewController = controller
        popup.contentSize = targetSize
        helpPopover = popup; rendered = fingerprint
        if parentHelp == nil, window.identifier?.rawValue == "DayPerk-preferences" {
            popup.show(relativeTo: bounds, of: self, preferredEdge: preferredEdge ?? .maxX)
        } else {
            // 主浮窗与每一级说明都作为避让区域，不能让系统翻转方向后压住已有窗口。
            // 原生说明窗的箭头和边框也占空间，锚点必须包含完整外框。
            var frameView = host
            while let superview = frameView.superview { frameView = superview }
            var obstacles = [window.frame]
            var ancestor = parentHelp
            while let help = ancestor {
                if let frame = help.window?.frame { obstacles.append(frame) }
                ancestor = help.parentHelp
            }
            guard showOutside(popup, host: frameView, obstacles: obstacles) else {
                closeExplanation()
                return
            }
        }
        controller.view.window?.identifier = NSUserInterfaceItemIdentifier("DayPerk-help")
        monitorClicks()
    }

    private func showOutside(_ popup: NSPopover, host: NSView, obstacles: [NSRect]) -> Bool {
        guard let screen = window?.screen?.visibleFrame else { return false }
        let question = host.convert(bounds, from: self)
        let leading = question.midX - host.bounds.minX <= host.bounds.maxX - question.midX
        let nearest = preferredEdge ?? (leading ? NSRectEdge.minX : .maxX)
        let outerWidth = popup.contentSize.width + 40
        let columns = [question.midX, host.bounds.minX + outerWidth / 2, host.bounds.maxX - outerWidth / 2]
        for edge in [nearest, nearest == .minX ? .maxX : .minX, .minY, .maxY] {
            let horizontal = edge == .maxX || edge == .minX
            let anchors = horizontal
                ? [NSRect(x: host.bounds.minX, y: question.minY, width: host.bounds.width, height: question.height)]
                : columns.map { NSRect(x: min(host.bounds.maxX - 1, max(host.bounds.minX, $0)), y: host.bounds.minY, width: 1, height: host.bounds.height) }
            for anchor in anchors {
                popup.show(relativeTo: anchor, of: host, preferredEdge: edge)
                if let frame = popup.contentViewController?.view.window?.frame,
                   screen.insetBy(dx: -1, dy: -1).contains(frame),
                   obstacles.allSatisfy({ !$0.intersects(frame) }) {
                    return true
                }
                popup.close()
            }
        }
        return false
    }

    func refreshIfVisible() {
        guard let helpPopover, helpPopover.isShown, rendered != fingerprint else { return }
        let content = makeContent()
        let targetSize = content.frame.size
        // 先记录新尺寸；赋给旧控制器会把新内容压回解锁页的旧尺寸。
        if targetSize != helpPopover.contentSize {
            closeExplanation()
            showExplanation()
            return
        }
        rendered = fingerprint
        helpPopover.contentViewController?.view = content
        helpPopover.contentViewController?.preferredContentSize = targetSize
        helpPopover.contentSize = targetSize
        content.window?.identifier = NSUserInterfaceItemIdentifier("DayPerk-help")
    }

    func makeContent() -> NSView {
        if let access, !access.canViewIncomeDetails {
            let view = NSHostingView(rootView: SalaryUnlockView(access: access).frame(width: 342, height: 230))
            view.sizingOptions = []
            view.frame = NSRect(x: 0, y: 0, width: 342, height: 230)
            return view
        }
        let width: CGFloat = formula != nil ? 378 : (options.isEmpty && hours == nil ? explanationWidth : 342)
        let bodyWidth = width - 32
        let label = NSTextField(wrappingLabelWithString: RuleHelpText.bulleted(explanation))
        label.font = .systemFont(ofSize: 13); label.textColor = .labelColor
        let textHeight = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: bodyWidth, height: 1200)).height ?? 18)
        let optionHeight = options.isEmpty ? 0 : CGFloat(options.count) * 26 + 14
        let showsRevoke = access?.settingsUnlocked == true
        let footerWidth = bodyWidth - (showsRevoke ? 100 : 0)
        let footer = NSTextField(wrappingLabelWithString: L10n.text(formulaFooter))
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        let footerHeight = max(showsRevoke ? 24 : 0, ceil(footer.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: footerWidth, height: 200)).height ?? 16))
        let rowHeights = formula?.map { row -> CGFloat in
            let name = NSTextField(wrappingLabelWithString: row.label)
            name.font = .systemFont(ofSize: 13, weight: row.isTotal ? .semibold : .regular)
            return max(22, ceil(name.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 196, height: 400)).height ?? 18) + 4)
        } ?? []
        let bodyHeight = formula.map { _ in 18 + 12 + rowHeights.reduce(0, +) + 12 + footerHeight } ?? textHeight
        let hoursHeight: CGFloat = hours == nil ? 0 : 34
        let height = 32 + optionHeight + hoursHeight + bodyHeight
        let view = HelpContainer(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.entered = { [weak self] in self?.pendingClose?.cancel() }
        view.exited = { [weak self] in self?.scheduleClose() }
        var y = height - 16
        for (index, option) in options.enumerated() {
            y -= 26
            let checkbox = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(changeOption(_:)))
            checkbox.font = .systemFont(ofSize: 13); checkbox.state = option.isOn ? .on : .off; checkbox.tag = index
            checkbox.frame = NSRect(x: 16, y: y, width: bodyWidth, height: 22)
            view.addSubview(checkbox)
        }
        if !options.isEmpty {
            y -= 14
        }
        if let hours {
            y -= 26
            let title = NSTextField(labelWithString: hours.title)
            title.font = .systemFont(ofSize: 13, weight: .medium)
            let titleWidth = min(bodyWidth - 28, title.cell?.cellSize.width ?? 180)
            title.frame = NSRect(x: 16, y: y + 3, width: titleWidth, height: 18)
            let nested = HoverHelpButton()
            nested.explanation = hours.detail; nested.parentHelp = self
            nested.formula = hours.rows
            nested.formulaTitle = L10n.text("ui.reference_work_hours.e292f271")
            nested.formulaFooter = L10n.text("ui.from_saved_settings_actual_time_fol.a72ee8fd")
            nested.setAccessibilityLabel(hours.detail)
            nested.frame = NSRect(x: 16 + titleWidth + 6, y: y + 3, width: 18, height: 18)
            view.addSubview(title); view.addSubview(nested)
            y -= 8
        }
        if let formula {
            y -= 18
            let heading = NSTextField(labelWithString: L10n.text(formulaTitle))
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            heading.frame = NSRect(x: 16, y: y, width: bodyWidth, height: 18); view.addSubview(heading)
            y -= 12
            for (index, row) in formula.enumerated() {
                let rowHeight = rowHeights[index]
                y -= rowHeight
                let amount = NSTextField(labelWithString: row.amount)
                amount.font = .monospacedDigitSystemFont(ofSize: 13, weight: row.isTotal ? .semibold : .regular); amount.alignment = .right
                amount.frame = NSRect(x: 16, y: y + (rowHeight - 18) / 2, width: 136, height: 18)
                let name = NSTextField(wrappingLabelWithString: row.label)
                name.font = .systemFont(ofSize: 13, weight: row.isTotal ? .semibold : .regular)
                name.frame = NSRect(x: 166, y: y + 2, width: 196, height: rowHeight - 4)
                if row.isTotal {
                    amount.textColor = AppearanceSettings.shared.theme.nsColor; name.textColor = AppearanceSettings.shared.theme.nsColor
                }
                view.addSubview(amount); view.addSubview(name)
            }
            footer.frame = NSRect(x: 16, y: 16, width: footerWidth, height: footerHeight); view.addSubview(footer)
            if showsRevoke {
                let revoke = NSButton(title: L10n.text("ui.revoke_access.1d966710"), target: self, action: #selector(revokeAuthorization))
                revoke.setAccessibilityLabel(L10n.text("ui.revoke_all_access.47d109d6"))
                revoke.bezelStyle = .rounded
                revoke.frame = NSRect(x: width - 104, y: 16, width: 88, height: 24)
                view.addSubview(revoke)
            }
        } else {
            label.frame = NSRect(x: 16, y: 16, width: bodyWidth, height: textHeight); view.addSubview(label)
        }
        return view
    }

    private var explanationWidth: CGFloat {
        guard let window, let screen = window.screen else { return 342 }
        let buttonFrame = window.convertToScreen(convert(bounds, to: nil))
        let available = max(screen.visibleFrame.maxX - buttonFrame.maxX, buttonFrame.minX - screen.visibleFrame.minX)
        // 空间不足时仍保留可读宽度，不能把说明压成逐字换行的细长条。
        return min(342, max(280, available - 32))
    }

    @objc private func changeOption(_ sender: NSButton) {
        guard options.indices.contains(sender.tag) else { return }
        options[sender.tag].change(sender.state == .on)
    }

    @objc private func revokeAuthorization() {
        access?.revokeAuthorization()
    }

    private func scheduleClose() {
        pendingClose?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.access?.isHandlingSystemAuthentication != true else { return }
            let point = NSEvent.mouseLocation
            let onButton = self.window.map { $0.convertToScreen(self.convert(self.bounds, to: nil)).contains(point) } ?? false
            let inPanel = self.containsInBranch(point)
            if !onButton && !inPanel {
                self.closeExplanation()
            }
        }
        pendingClose = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func monitorClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.access?.isHandlingSystemAuthentication != true else { return event }
            if event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                return event
            }
            if self.isWindowInBranch(event.window) {
                return event
            }
            self.closeExplanation(); return event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in DispatchQueue.main.async {
            guard self?.access?.isHandlingSystemAuthentication != true else { return }
            self?.closeExplanation()
        } }
        deactivate = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.access?.isHandlingSystemAuthentication != true else { return }
            self?.closeExplanation()
        }
    }

    private func closeExplanation() {
        pendingClose?.cancel()
        childHelp?.closeExplanation(); childHelp = nil
        helpPopover?.close()
        helpPopover = nil
        if Self.activeHelp === self {
            Self.activeHelp = parentHelp
        }
        if parentHelp?.childHelp === self {
            parentHelp?.childHelp = nil
        }
        if let localClicks {
            NSEvent.removeMonitor(localClicks)
        }; localClicks = nil
        if let globalClicks {
            NSEvent.removeMonitor(globalClicks)
        }; globalClicks = nil
        if let deactivate {
            NotificationCenter.default.removeObserver(deactivate)
        }; deactivate = nil
    }

    static func closeActive() {
        activeHelp?.rootHelp.closeExplanation()
    }

    private var rootHelp: HoverHelpButton {
        parentHelp?.rootHelp ?? self
    }

    private func containsInBranch(_ point: NSPoint) -> Bool {
        (helpPopover?.isShown == true && (helpPopover?.contentViewController?.view.window?.frame.contains(point) ?? false))
            || (childHelp?.containsInBranch(point) ?? false)
    }

    private func isWindowInBranch(_ window: NSWindow?) -> Bool {
        window != nil && (window === helpPopover?.contentViewController?.view.window || (childHelp?.isWindowInBranch(window) ?? false))
    }
}

struct SalaryUnlockView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject var access: SalaryAccessController
    var settings = false
    var openSettings: (() -> Void)?
    var controls: DayPerkModel?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield").font(.system(size: 38)).foregroundStyle(appearance.theme.color)
            Text(access.isDataLocked ? L10n.text("ui.all_data_locked.4d971861") : settings ? L10n.text("ui.personal_pay_data_locked.7c5c22a5") : L10n.text("ui.income_breakdown_locked.d9f49566")).font(.title3.weight(.semibold))
            Text(L10n.text("ui.unlock_with_touch_id_or_your_mac_lo.63a2ffa2")).foregroundStyle(.secondary)
            Button(L10n.text("ui.unlock.7bf1885f")) {
                if access.isDataLocked {
                    access.unlockAllData()
                } else if settings {
                    access.unlockSettings()
                } else {
                    access.unlockIncomeDetails()
                }
            }.buttonStyle(BrewButtonStyle(prominent: true)).disabled(access.isAuthenticating)
            if let controls {
                Divider()
                LockedWorkControls(tracking: controls.tracking)
            }
            if let openSettings {
                Button(L10n.text("ui.settings.df3d58c7"), action: openSettings)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle())
    }
}

private struct LockedWorkControls: View {
    @ObservedObject var tracking: WorkTrackingController

    var body: some View {
        Toggle(L10n.text("ui.caffeine_keep_awake.06a5f5a3"), isOn: Binding(get: { tracking.state.caffeineEnabled }, set: { tracking.setCaffeine($0) }))
        Toggle(L10n.text("ui.working_track_earnings.6c6c56ea"), isOn: Binding(get: { tracking.state.isWorking }, set: { tracking.setWorking($0) }))
    }
}

struct DayPerkDashboardView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject var model: DayPerkModel
    @ObservedObject private var language = LocalizationManager.shared
    var openSettings: (PreferencePage) -> Void
    private var showcaseMode: Bool { model.privacy.isStatisticsShowcaseEnabled }
    private var workStatus: DashboardWorkStatus {
        DashboardWorkStatus(isWorking: model.tracking.state.isWorking, isSettled: model.isTodaySettled,
            isRegisteredOvertime: model.isOvertime, exceededReference: model.hasExceededReferenceHours)
    }

    var body: some View {
        Group {
            if model.access.isDataLocked {
                SalaryUnlockView(access: model.access, controls: model).frame(width: 430)
            } else {
                dashboardContent
            }
        }.fixedSize(horizontal: false, vertical: true)
            .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["panel-content"] = anchor }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // 只测量内容，窗口仍由 AppKit 手动定尺寸。
                model.recordPanelContentHeights([model.panelLayoutMode: height])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .preferredColorScheme(.dark).tint(appearance.theme.color).environment(\.locale, language.currentLocale)
            .buttonStyle(BrewButtonStyle()).toggleStyle(BrewToggleStyle())
            .background(BrewBackground(appearance: appearance, panel: true))
            .modifier(PaydayBackdrop(started: model.paydayCelebration?.started))
            .overlay {
                if let celebration = model.clockOutCelebration, !model.access.isDataLocked, !model.privacy.isPrivacyModeEnabled {
                    ClockOutCelebration(started: celebration.started).allowsHitTesting(false).accessibilityHidden(true)
                }
                if let celebration = model.paydayCelebration, !model.access.isDataLocked, !model.privacy.isPrivacyModeEnabled {
                    PaydayCelebrationView(language: language.effectiveLanguageCode, theme: appearance.theme,
                        didStart: { model.paydayAnimationDidStart(id: celebration.id) },
                        didFinish: { model.endPaydayCelebration(id: celebration.id) })
                        .id(celebration.id).allowsHitTesting(false).accessibilityHidden(true)
                        .onDisappear { model.endPaydayCelebration(id: celebration.id) }
                }
            }.clipped()
            .actionToastHost()
            .onChange(of: model.access.authenticationMessage) { _, text in ActionToastCenter.shared.show(text, isError: true) }
            .onChange(of: model.actionError ?? model.tracking.errorMessage) { _, text in
                if let text { ActionToastCenter.shared.show(text, isError: true) }
            }
            .onChange(of: model.privacy.isPrivacyModeEnabled) { _, hidden in
                if hidden { HoverHelpButton.closeActive(); model.endClockOutCelebration() }
            }
            .onChange(of: model.access.isDataLocked) { _, locked in if locked { model.endClockOutCelebration() } }
            .onChange(of: showcaseMode) { _, _ in HoverHelpButton.closeActive() }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                OverflowAmount(text: amount(model.today.earned, currencyCode: model.today.currencyCode), size: 38, weight: .medium)
                    .foregroundStyle(appearance.theme.color)
                Spacer()
                Text(L10n.text(workStatus.titleKey))
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(workStatus == .unpaidOvertime ? Color.red : workStatus == .clockedOut ? .green : workStatus == .paused ? .gray : appearance.theme.color)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["header"] = anchor }
            HStack {
                let summary = L10n.text(model.today.trackingSummary(registeredOvertime: model.overtimeDates[model.today.id] != nil))
                Text(showcaseMode ? WorkReportPresentation.maskNumbers(summary) : summary)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
            }.transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["tracking-summary"] = anchor }
            VStack(spacing: 16) {
                switchRow(L10n.text("ui.caffeine_keep_awake.06a5f5a3"), value: Binding(get: { model.tracking.state.caffeineEnabled }, set: { model.tracking.setCaffeine($0) }),
                          help: model.caffeineRuleExplanation)
                Divider()
                switchRow(L10n.text("ui.working_track_earnings.6c6c56ea"), value: Binding(get: { model.tracking.state.isWorking }, set: { model.tracking.setWorking($0) }),
                          help: model.trackingRuleExplanation)
            }.padding(16).background(appearance.theme.surface.opacity(appearance.background.enabled ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 12)).transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["work-controls"] = anchor }
            Divider()
            // 两套内容共同决定卡片尺寸，结算只切换可见内容，底部按钮不随之跳动。
            ZStack {
                VStack(spacing: 14) {
                    GeometryReader { geometry in
                        let title = L10n.text(model.settledBalanceTitle)
                        let value = amount(abs(model.settledBalance), currencyCode: model.today.currencyCode, isBalance: true)
                        let measuredValue = OverflowAmount.width(value, size: 30, weight: .semibold)
                        let titleWidth = min((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold)]).width + 2,
                                             geometry.size.width - min(measuredValue, geometry.size.width * 0.6) - 12)
                        let valueWidth = min(measuredValue, geometry.size.width - titleWidth - 12)
                        HStack(spacing: 12) {
                            Text(title).font(.system(size: 18, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85)
                                .multilineTextAlignment(.trailing).frame(width: titleWidth, alignment: .trailing)
                            OverflowAmount(text: value, size: 30).foregroundStyle(balanceColor).frame(width: valueWidth)
                        }.fixedSize(horizontal: true, vertical: false)
                            .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in
                                if model.isTodaySettled { value["daily-balance"] = anchor }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                    }.frame(height: 48)
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        rateMetric()
                        monthMetric()
                        expectedMetric()
                    }
                }.opacity(model.isTodaySettled ? 1 : 0)
                    .allowsHitTesting(model.isTodaySettled).accessibilityHidden(!model.isTodaySettled)
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 16) { rateMetric(large: true); monthMetric(large: true) }
                    HStack(alignment: .top, spacing: 16) {
                        expectedMetric(large: true)
                        metric(L10n.text("dashboard.today_balance"), value: amount(model.settledBalance, currencyCode: model.today.currencyCode, isBalance: true), alignment: .center,
                               help: L10n.text("ui.a_positive_balance_is_time_value_ga.546054ae"),
                               warning: (!model.privacy.isPrivacyModeEnabled || showcaseMode) && model.settledBalance < -0.005,
                               success: (!model.privacy.isPrivacyModeEnabled || showcaseMode) && model.hasSecuredDepartureSurplus && model.settledBalance > 0.005, large: true)
                            .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in
                                if !model.isTodaySettled { value["daily-balance"] = anchor }
                            }
                    }
                }.opacity(model.isTodaySettled ? 0 : 1)
                    .allowsHitTesting(!model.isTodaySettled).accessibilityHidden(model.isTodaySettled)
            }.padding(16).background(appearance.theme.surface.opacity(appearance.background.enabled ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 12)).transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["daily-summary"] = anchor }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("ui.estimated_take_home_pay.c2558b90")).font(.caption).foregroundStyle(.secondary)
                    InfoHelp(text: model.salaryExplanation, formula: model.salaryFormulaRows, options: model.withdrawableBenefits.map { item in
                        HelpOption(title: L10n.format("benefits.show_item", item.displayName), isOn: item.showInEstimate) {
                            model.updateBenefitOptions(id: item.id, showInEstimate: $0)
                        }
                    }, access: model.access).frame(width: 18, height: 18)
                        .opacity(showcaseMode ? 0 : 1).allowsHitTesting(!showcaseMode).accessibilityHidden(showcaseMode)
                    Spacer()
                    Text(L10n.text("ui.payday.3ea9afa9")).font(.caption).foregroundStyle(.secondary)
                    Text(model.paydayLabel).font(.caption).monospacedDigit()
                }
                OverflowAmount(text: model.takeHomeEstimateFormula, size: model.benefitForEstimate > 0 ? 14 : 17, weight: .medium)

            }.transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["pay-summary"] = anchor }
            HStack(spacing: 6) {
                settingsButton; lockButton; privacyButton
                if model.workStatus.data.enabled { WorkStatusMenu(controller: model.workStatus) }
                Spacer(minLength: 0)
                clockOutButton
                ShowcaseModeButton(model: model, helpKey: "dashboard.showcase_help")
                    .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["showcase"] = anchor }
                quitButton
                    .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["quit"] = anchor }
            }.controlSize(.small).lineLimit(1)
                .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["footer"] = anchor }

        }.padding(22).frame(width: 430).preferredColorScheme(.dark).tint(appearance.theme.color)
            .environment(\.locale, language.currentLocale)
    }

    private func rateMetric(large: Bool = false) -> some View {
        metric(L10n.text("ui.time_value_rate.7f5be965"), value: L10n.text(L10n.format("ui.1.aee4ea58", String(describing: amount(model.minuteRate, currencyCode: model.isTodaySettled ? model.today.currencyCode : nil)))), alignment: .center, help: model.rateExplanation, options: [
                        HelpOption(title: L10n.text("ui.include_annual_bonus.e30ae43d"), isOn: model.payroll.includeAnnualBonus) { model.updateRateOptions(annualBonus: $0) },
                    ] + model.withdrawableBenefits.map { item in
                        HelpOption(title: L10n.format("benefits.include_item", item.displayName), isOn: item.includeInRate) {
                            model.updateBenefitOptions(id: item.id, includeInRate: $0)
                        }
                    } + [
                        HelpOption(title: L10n.text("ui.deduct_tax_employee_contributions.176b107c"), isOn: model.payroll.isEnabled) { model.updateRateOptions(deduct: $0) },
                    ], hours: model.workHoursExplanation, large: large)
    }
    private func monthMetric(large: Bool = false) -> some View {
        metric(L10n.text("ui.monthly_time_value.f7582b0b"), value: amount(model.monthEarned), alignment: .center, large: large)
    }
    private func expectedMetric(large: Bool = false) -> some View {
        metric(L10n.text("ui.today_s_expected_income.2bf2322e"), value: amount(model.expectedIncome(for: model.today), currencyCode: model.today.currencyCode), alignment: .center, large: large)
    }

    private var balanceColor: Color {
        guard !model.privacy.isPrivacyModeEnabled || showcaseMode else { return .primary }
        if model.settledBalance < -0.005 { return .red }
        return model.settledBalance > 0.005 ? .green : .primary
    }
    private var settingsButton: some View {
        Button { openSettings(.salary) } label: {
            Label(L10n.text("ui.settings.df3d58c7"), systemImage: "slider.horizontal.3").labelStyle(.iconOnly).frame(width: 16, height: 16)
        }.help(Text(L10n.text("ui.settings.df3d58c7")))
    }
    private var lockButton: some View {
        Button(L10n.text("ui.lock_all.32e12e99"), systemImage: "lock.fill") { model.access.lockAllData() }
            .labelStyle(.iconOnly).frame(minWidth: 24)
            .help(Text(L10n.text("ui.lock_all.32e12e99")))
    }
    private var privacyButton: some View {
        Button(LocalizedStringKey(model.privacy.isPrivacyModeEnabled ? L10n.text("ui.show_sensitive.43068b4c") : L10n.text("ui.hide_sensitive.f436386c")),
               systemImage: model.privacy.isPrivacyModeEnabled ? "eye" : "eye.slash") {
            model.access.setSensitiveInformationHidden(!model.privacy.isPrivacyModeEnabled, privacy: model.privacy)
        }.labelStyle(.iconOnly).frame(minWidth: 24)
            .help(Text(LocalizedStringKey(model.privacy.isPrivacyModeEnabled ? L10n.text("ui.show_sensitive.43068b4c") : L10n.text("ui.hide_sensitive.f436386c"))))
    }
    private var clockOutButton: some View {
        Button(LocalizedStringKey(model.isTodaySettled ? L10n.text("ui.back_to_work.671b04a8") : L10n.text(model.tracking.plan.hasReachedShiftEnd(Date(), calendar: model.workCalendar) ? "clockout.action" : "ui.clock_out_early.6b901f17"))) {
            if model.isTodaySettled { model.endClockOutCelebration(); model.tracking.setWorking(true) }
            else { model.finishToday() }
        }.buttonStyle(BrewButtonStyle(prominent: true))
            .disabled(!model.tracking.plan.canClockOut(Date(), calendar: model.workCalendar))
            .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["clock-out"] = anchor }
    }
    private var quitButton: some View {
        Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
            Label(L10n.text("ui.quit.498e1d59"), systemImage: "power").labelStyle(.iconOnly).frame(width: 16, height: 16).foregroundStyle(.red)
        }.help(Text(L10n.text("ui.quit.498e1d59")))
    }

    private func switchRow(_ title: String, value: Binding<Bool>, help: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.headline)
            InfoHelp(text: help).frame(width: 18, height: 18)
            Spacer(minLength: 12)
            Toggle(LocalizedStringKey(title), isOn: value).labelsHidden().toggleStyle(BrewToggleStyle(showsLabel: false))
                .accessibilityLabel(Text(LocalizedStringKey(title))).fixedSize()
        }
    }

    private func metric(_ title: String, value: String, alignment: HorizontalAlignment, help: String? = nil, options: [HelpOption] = [], hours: WorkHoursExplanation? = nil, preferredEdge: NSRectEdge? = nil, warning: Bool = false, success: Bool = false, large: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: large ? 8 : 7) {
            HStack(spacing: 5) {
                Text(LocalizedStringKey(title)).font(.system(size: large ? 14 : 12, weight: large ? .medium : .regular)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                if let help, !showcaseMode {
                    InfoHelp(text: help, options: options, hours: hours, preferredEdge: preferredEdge).frame(width: 18, height: 18)
                }
            }.frame(minHeight: 28)
            OverflowAmount(text: value, size: large ? 21 : 15, weight: large ? .semibold : .medium, alignment: .center).foregroundStyle(success ? Color.green : warning ? Color.red : Color.primary)
        }.frame(maxWidth: .infinity)
    }

    private func amount(_ value: Double, currencyCode: String? = nil, isBalance: Bool = false) -> String {
        WorkReportPresentation.money(model.currency.formatAmount(value, currencyCode: currencyCode), showcase: showcaseMode,
            unlocked: !showcaseMode || model.access.settingsUnlocked, privacyEnabled: model.privacy.isPrivacyModeEnabled,
            isBalance: isBalance, balanceIsIncome: !WorkReportPresentation.canShareBalance(
                expectedIncome: model.expectedIncome(for: model.today), timeValue: model.today.earned))
    }

}

struct ShowcaseModeButton: View {
    @ObservedObject var model: DayPerkModel
    var helpKey = "report.showcase_help"

    var body: some View {
        Button {
            HoverHelpButton.closeActive()
            model.privacy.isStatisticsShowcaseEnabled.toggle()
            // 先遮盖再验证，验证完成之前不公开差额。
            if model.privacy.isStatisticsShowcaseEnabled && !model.access.settingsUnlocked { model.access.unlockSettings() }
            ActionToastCenter.shared.show(L10n.text(model.privacy.isStatisticsShowcaseEnabled ? "report.showcase_on" : "report.showcase_off"))
        } label: {
            Image(systemName: "camera").frame(width: 16, height: 16)
        }.buttonStyle(BrewButtonStyle(prominent: model.privacy.isStatisticsShowcaseEnabled))
            .accessibilityLabel(L10n.text("report.showcase"))
            .accessibilityIdentifier("showcase-mode")
            .accessibilityValue(L10n.text(model.privacy.isStatisticsShowcaseEnabled ? "report.showcase_on" : "report.showcase_off"))
            .help(L10n.text(helpKey)).disabled(model.access.isAuthenticating)
    }
}

enum StatusBarPresentation {
    static func isOverdue(seconds: Double, referenceMinutes: Int) -> Bool {
        seconds.isFinite && referenceMinutes > 0 && seconds > Double(referenceMinutes) * 60
    }
    static func amount(_ value: Double, privateMode: Bool, showcase: Bool = false, decimalPlaces: Int = 0, isWorking: Bool = true, hideWhenPaused: Bool = true, retainForCelebration: Bool = false) -> String {
        guard !privateMode, !showcase, isWorking || !hideWhenPaused || retainForCelebration else { return "" }
        return String(format: "%.*f", min(2, max(0, decimalPlaces)), value.isFinite ? max(0, value) : 0)
    }
}

/// 咖啡杯交互与蒸汽造型参考 domzilla/Caffeine（MIT），许可随应用分发。
/// 从应用图标提炼侧斜杯口、右侧杯把与双层杯碟；模板只使用透明度，不固化黑白颜色。
enum CoffeeStatusIcon {
    static func make(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 20), flipped: false) { _ in
            NSColor.black.set()
            NSGraphicsContext.saveGraphicsState()
            // 两种状态共用杯身坐标，开关仅增减热气，避免图标上下跳动。
            let tilt = AffineTransform(translationByX: 12, byY: 8)
            var transform = tilt
            transform.rotate(byDegrees: 3)
            transform.translate(x: -12, y: -8)
            let saucer = NSBezierPath(ovalIn: NSRect(x: 1.2, y: 1.7, width: 20.8, height: 5.2))
            saucer.appendOval(in: NSRect(x: 3.2, y: 3.1, width: 16.8, height: 2.5))
            saucer.windingRule = .evenOdd
            saucer.transform(using: transform); saucer.fill()
            // 杯身与杯把使用连续轮廓和相切曲线，消除拼接处的折角与底部凸起。
            let cup = NSBezierPath()
            cup.move(to: NSPoint(x: 3.7, y: 12))
            cup.curve(to: NSPoint(x: 17.5, y: 13.05), controlPoint1: NSPoint(x: 3.7, y: 15.2), controlPoint2: NSPoint(x: 15.6, y: 15.2))
            cup.curve(to: NSPoint(x: 18.3, y: 12.4), controlPoint1: NSPoint(x: 17.85, y: 12.65), controlPoint2: NSPoint(x: 17.95, y: 12.4))
            cup.curve(to: NSPoint(x: 20.15, y: 13.05), controlPoint1: NSPoint(x: 18.65, y: 12.4), controlPoint2: NSPoint(x: 19.2, y: 13.05))
            cup.curve(to: NSPoint(x: 22.6, y: 10.8), controlPoint1: NSPoint(x: 21.65, y: 13.05), controlPoint2: NSPoint(x: 22.6, y: 12.1))
            cup.curve(to: NSPoint(x: 16.3, y: 6), controlPoint1: NSPoint(x: 22.6, y: 8.6), controlPoint2: NSPoint(x: 18.6, y: 8.3))
            cup.curve(to: NSPoint(x: 6, y: 5.7), controlPoint1: NSPoint(x: 14, y: 3.7), controlPoint2: NSPoint(x: 7.2, y: 4.3))
            cup.curve(to: NSPoint(x: 3.7, y: 12), controlPoint1: NSPoint(x: 4.6, y: 7.333), controlPoint2: NSPoint(x: 3.7, y: 9.2))
            cup.close()
            cup.appendOval(in: NSRect(x: 5.2, y: 11.4, width: 11.3, height: 2))
            cup.move(to: NSPoint(x: 18.25, y: 10.9))
            cup.curve(to: NSPoint(x: 19.8, y: 11.95), controlPoint1: NSPoint(x: 18.6, y: 11.65), controlPoint2: NSPoint(x: 19.1, y: 11.95))
            cup.curve(to: NSPoint(x: 21.2, y: 10.8), controlPoint1: NSPoint(x: 20.65, y: 11.95), controlPoint2: NSPoint(x: 21.2, y: 11.5))
            cup.curve(to: NSPoint(x: 17.9, y: 8.05), controlPoint1: NSPoint(x: 21.2, y: 9.65), controlPoint2: NSPoint(x: 19.6, y: 8.75))
            cup.curve(to: NSPoint(x: 17.55, y: 8.4), controlPoint1: NSPoint(x: 17.6, y: 7.9265), controlPoint2: NSPoint(x: 17.45, y: 8.05))
            cup.curve(to: NSPoint(x: 18.25, y: 10.9), controlPoint1: NSPoint(x: 17.85, y: 9.45), controlPoint2: NSPoint(x: 17.9, y: 10.15))
            cup.close()
            cup.windingRule = .evenOdd
            cup.transform(using: transform); cup.fill()
            // 镂空细线区分杯沿和杯脚，保留模板在浅色、深色菜单栏中的反转能力。
            NSGraphicsContext.saveGraphicsState()
            cup.addClip()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let rim = NSBezierPath()
            rim.move(to: NSPoint(x: 4.4, y: 10.9))
            rim.curve(to: NSPoint(x: 17.4, y: 10.9), controlPoint1: NSPoint(x: 6.5, y: 8.7), controlPoint2: NSPoint(x: 15, y: 8.7))
            rim.lineWidth = 0.85; rim.transform(using: transform); rim.stroke()
            let foot = NSBezierPath()
            foot.move(to: NSPoint(x: 6, y: 6.4))
            foot.curve(to: NSPoint(x: 16.3, y: 6.6), controlPoint1: NSPoint(x: 8.3, y: 4.9), controlPoint2: NSPoint(x: 14.6, y: 5.1))
            foot.lineWidth = 0.7; foot.transform(using: transform); foot.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.restoreGraphicsState()
            if active {
                for (x, height) in [(6.0, 3.5), (10.0, 3.7), (14.0, 3.5)] {
                    let steam = NSBezierPath()
                    steam.move(to: NSPoint(x: x, y: 15.3))
                    steam.curve(to: NSPoint(x: x + 0.6, y: 15.3 + height),
                                controlPoint1: NSPoint(x: x - 1.8, y: 16.7), controlPoint2: NSPoint(x: x + 2.2, y: 17.7))
                    steam.lineWidth = 0.95; steam.lineCapStyle = .round; steam.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// 状态取计时和结算结果，超过参考工时优先显示无偿加班。
enum DashboardWorkStatus: Equatable {
    case working, paused, overtime, unpaidOvertime, clockedOut
    init(isWorking: Bool, isSettled: Bool, isRegisteredOvertime: Bool, exceededReference: Bool) {
        if isSettled { self = .clockedOut }
        else if !isWorking { self = .paused }
        else if exceededReference { self = .unpaidOvertime }
        else { self = isRegisteredOvertime ? .overtime : .working }
    }
    var titleKey: String {
        switch self {
        case .working: return "ui.working.f4208226"
        case .paused: return "ui.paused.eb0c326b"
        case .overtime: return "ui.overtime.00b738a1"
        case .unpaidOvertime: return "dashboard.unpaid_overtime_active"
        case .clockedOut: return "ui.clocked_out.c437314b"
        }
    }
}
