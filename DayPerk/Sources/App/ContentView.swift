// DayPerk，许可条款见仓库 LICENSE。
import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private(set) var model = DayPerkModel()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var preferencesWindow: NSWindow?
    private var preferencesHostingController: NSHostingController<DayPerkPreferencesView>?
    private var dashboardWindow: NSWindow?
    private var cancellable: AnyCancellable?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var securityObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var authenticationWindow: NSWindow?
    private let inactiveIcon = CoffeeStatusIcon.make(active: false)
    private let activeIcon = CoffeeStatusIcon.make(active: true)
    private let statusClicks = StatusItemClickHandler()
    private var statusPressWasDouble = false

    override init() {
        super.init()
        // 首次空库可直接设置；已有数据时先上锁，再建立任何金额界面。
        if !model.access.settingsUnlocked { model.access.lockAllData() }
        bindModel()
        popover.behavior = .applicationDefined
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let hosting = NSHostingController(rootView: DayPerkDashboardView(model: model) { [weak self] page in
            self?.showSettingsWindow(page: page)
        })
        // 固定尺寸由 AppKit 管理，避免系统反复按 SwiftUI 内容调整窗口形成布局循环。
        hosting.sizingOptions = []; hosting.safeAreaRegions = []
        (hosting.view as? NSHostingView<DayPerkDashboardView>)?.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 430, height: model.preferredPanelHeight)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        updateStatusBar()
        let appCenter = NotificationCenter.default
        securityObservers.append((appCenter, appCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.model.access.isHandlingSystemAuthentication else { return }
            HoverHelpButton.closeActive()
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            securityObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.model.access.handleSystemInterruption()
                self?.showPopover = false
                HoverHelpButton.closeActive()
            }))
        }
    }

    private func bindModel() {
        model.access.authenticationWillBegin = { [weak self] in self?.authenticationWindow = NSApp.keyWindow }
        model.access.authenticationDidFinish = { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            if self.popover.isShown {
                self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            } else if let window = self.authenticationWindow, window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
        model.restoreBackup = { [weak self] archive in
            guard let self else { return }
            _ = try AppDataBackup.validate(archive)
            self.model.tracking.checkpoint()
            self.model.workStatus.checkpoint()
            let current = try AppDataBackup.create()
            let directory = UserDataStore.directory.appendingPathComponent("Backups")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try AppDataBackup.encoded(current).write(to: directory.appendingPathComponent("before-import-" + UUID().uuidString + ".dayperk"), options: .atomic)
            try AppDataBackup.restore(archive)
            self.cancellable?.cancel()
            self.model.tracking.discardForRestore(); self.model.access.revokeAuthorization()
            HoverHelpButton.closeActive(); self.showPopover = false
            self.preferencesWindow?.close(); self.preferencesWindow = nil
            self.dashboardWindow?.close(); self.dashboardWindow = nil
            PayrollDeductionSettings.shared.reloadFromStorage(); MoneyDisplaySettings.shared.reloadFromStorage()
            AppearanceSettings.shared.reloadFromStorage(); RegionalHolidayCalendar.shared.reloadFromStorage(); MainActor.assumeIsolated { ChinaHolidayCalendar.shared.reloadFromStorage() }
            LocalizationManager.shared.setLanguage(AppLanguage(rawValue: UserDataStore.shared.string(forKey: "appLanguage") ?? "en") ?? .english)
            self.model = DayPerkModel(restoringBackup: true)
            self.model.access.lockAllData()
            MainActor.assumeIsolated { LaunchAtLoginManager.shared.restoreSavedPreference() }
            self.bindModel()
            let hosting = NSHostingController(rootView: DayPerkDashboardView(model: self.model) { [weak self] page in self?.showSettingsWindow(page: page) })
            hosting.sizingOptions = []; hosting.safeAreaRegions = []; (hosting.view as? NSHostingView<DayPerkDashboardView>)?.sizingOptions = []
            self.popover.contentViewController = hosting
            self.model.tracking.resumeImportedControls()
            self.updateStatusBar(); self.showSettingsWindow(page: .data)
        }
        cancellable = model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatusBar() }
    }

    deinit { securityObservers.forEach { $0.0.removeObserver($0.1) } }

    var showPopover: Bool {
        get { popover.isShown }
        set {
            if newValue, let button = item.button {
                HoverHelpButton.closeActive()
                dashboardWindow?.orderOut(nil)
                preferencesWindow?.orderOut(nil)
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                monitorOutsideClicks()
            } else {
                popover.performClose(nil); removeMonitors()
            }
        }
    }

    private func monitorOutsideClicks() {
        removeMonitors()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.model.access.isHandlingSystemAuthentication != true else { return }
                self?.showPopover = false
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            if let self, !self.model.access.isHandlingSystemAuthentication, event.window !== self.popover.contentViewController?.view.window,
               event.window !== self.item.button?.window,
               event.window?.identifier?.rawValue != "DayPerk-help"
            {
                self.showPopover = false
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.model.access.isHandlingSystemAuthentication != true else { return }
            self?.showPopover = false
        }
    }

    private func removeMonitors() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
        }; outsideMonitor = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }; localMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }; resignObserver = nil
    }

    func popoverDidClose(_: Notification) {
        removeMonitors(); HoverHelpButton.closeActive()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .rightMouseDown {
            if event.type == .rightMouseDown { statusClicks.cancel(); statusPressWasDouble = false }
            else { statusPressWasDouble = statusClicks.beginPress() }
            return
        }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusClicks.cancel()
            let menu = NSMenu()
            let settings = NSMenuItem(title: L10n.text("ui.settings.148d195e"), action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self; menu.addItem(settings)
            menu.addItem(NSMenuItem(title: L10n.text("ui.quit.498e1d59"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            let isDouble = statusPressWasDouble
            statusPressWasDouble = false
            statusClicks.handle(clickCount: isDouble ? 2 : 1, single: { [weak self] in
                guard let self else { return }
                self.showPopover.toggle()
            }, double: { [weak self] in
                guard let self else { return }
                self.model.access.lockAllData()
                self.showPopover = false
                self.dashboardWindow?.orderOut(nil)
                HoverHelpButton.closeActive()
            })
        }
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    func showDashboardWindow() {
        preferencesWindow?.orderOut(nil)
        popover.performClose(nil)
        if dashboardWindow == nil {
            let view = DayPerkDashboardView(model: model) { [weak self] page in
                self?.showSettingsWindow(page: page)
            }
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = []; hosting.safeAreaRegions = []
            (hosting.view as? NSHostingView<DayPerkDashboardView>)?.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.setContentSize(NSSize(width: 430, height: model.preferredPanelHeight))
            window.delegate = self
            window.title = LocalPreviewMode.enabled ? L10n.text("ui.dayperk_preview_sample_data.73e6329b") : L10n.text("ui.dayperk_work_panel.951a3ff9")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettingsWindow(page: PreferencePage = .salary) {
        HoverHelpButton.closeActive()
        dashboardWindow?.orderOut(nil)
        popover.performClose(nil)
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesWindowLayout.defaultSize),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            window.title = LocalPreviewMode.enabled ? L10n.text("ui.dayperk_preview_sample_data.73e6329b") : L10n.text("ui.dayperk_settings.0718069b")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.identifier = NSUserInterfaceItemIdentifier("DayPerk-preferences")
            window.setContentSize(PreferencesWindowLayout.defaultSize)
            window.minSize = PreferencesWindowLayout.minimumSize
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        guard let window = preferencesWindow else { return }
        let hosting = NSHostingController(rootView: DayPerkPreferencesView(model: model, initialPage: page))
        hosting.sizingOptions = []; hosting.safeAreaRegions = []
        (hosting.view as? NSHostingView<DayPerkPreferencesView>)?.sizingOptions = []
        PreferencesWindowLayout.install(hosting.view, in: window)
        preferencesHostingController = hosting
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        HoverHelpButton.closeActive()
    }

    func shutdown() {
        removeMonitors(); model.tracking.shutdown()
    }

    private func updateStatusBar() {
        let size = NSSize(width: 430, height: model.preferredPanelHeight)
        if popover.contentSize != size { popover.contentSize = size }
        if let window = dashboardWindow, window.contentView?.frame.size != size { window.setContentSize(size) }
        preferencesWindow?.title = LocalPreviewMode.enabled ? L10n.text("ui.dayperk_preview_sample_data.73e6329b") : L10n.text("ui.dayperk_settings.0718069b")
        dashboardWindow?.title = LocalPreviewMode.enabled ? L10n.text("ui.dayperk_preview_sample_data.73e6329b") : L10n.text("ui.dayperk_work_panel.951a3ff9")
        preferencesWindow?.backgroundColor = model.appearance.theme.canvasNSColor
        dashboardWindow?.backgroundColor = model.appearance.theme.canvasNSColor
        guard let button = item.button else { return }
        button.image = model.tracking.state.caffeineEnabled ? activeIcon : inactiveIcon
        // 杯子保持模板图，由系统决定黑白；警示色仅赋给数字。
        button.contentTintColor = nil
        let amount = StatusBarPresentation.amount(model.today.earned, privateMode: model.privacy.isPrivacyModeEnabled || model.access.isDataLocked, showcase: model.privacy.isStatisticsShowcaseEnabled, decimalPlaces: model.currency.menuBarDecimalPlaces, isWorking: model.tracking.state.isWorking, hideWhenPaused: model.access.hideWhenPaused, retainForCelebration: model.clockOutCelebration?.retainsMenuAmount(at: Date()) == true)
        let displayAmount = LocalPreviewMode.enabled ? "TEST" + (amount.isEmpty ? "" : " · " + amount) : amount
        button.imagePosition = displayAmount.isEmpty ? .imageOnly : .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        var attributes: [NSAttributedString.Key: Any] = [.font: button.font!]
        if model.hasExceededReferenceHours { attributes[.foregroundColor] = NSColor.systemRed }
        button.attributedTitle = NSAttributedString(string: displayAmount.isEmpty ? "" : " " + displayAmount, attributes: attributes)
        button.toolTip = LocalPreviewMode.enabled ? L10n.text("ui.preview_sample_data.5f5a29be") : model.tracking.state.isWorking ? L10n.text("ui.dayperk_tracking_work.2efb2bd4") : L10n.text("ui.dayperk_tracking_paused.57f483bb")
        button.setAccessibilityLabel(L10n.text("ui.dayperk_caffeine_and_work_tracking.01026205"))
        button.setAccessibilityValue(button.toolTip)
    }
}

/// 使用较短的组合点击窗口；第二次按下即取消单击，双击只静默锁定。
final class StatusItemClickHandler {
    private var pending: DispatchWorkItem?
    private let interval: TimeInterval
    init(interval: TimeInterval = 0.2) { self.interval = interval }
    deinit { pending?.cancel() }
    func cancel() { pending?.cancel(); pending = nil }
    func beginPress() -> Bool {
        let isDouble = pending != nil
        if isDouble { cancel() }
        return isDouble
    }
    func handle(clickCount: Int, single: @escaping () -> Void, double: () -> Void) {
        cancel()
        if clickCount == 2 { double(); return }
        guard clickCount == 1 else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.pending?.isCancelled == false else { return }
            self.pending = nil
            single()
        }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: task)
    }
}
