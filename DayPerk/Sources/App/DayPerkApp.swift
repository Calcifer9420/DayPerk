// DayPerk，许可条款见仓库 LICENSE。
import SwiftUI

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    private var storageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let error = UserDataStore.shared.readError {
            NSAlert(error: error).runModal(); NSApp.terminate(nil); return
        }
        storageObserver = NotificationCenter.default.addObserver(forName: .dayPerkStorageFailed, object: nil, queue: .main) { notification in
            if let error = notification.object as? Error { NSAlert(error: error).runModal() }
        }
        LogService.info(L10n.text("ui.application_started.558781bd"))

        // 自动测试与文档截图宿主不创建菜单栏图标，避免和日常版同时出现。
        if let identifier = Bundle.main.bundleIdentifier,
           identifier.hasPrefix("app.dayperk.tests.") || identifier.hasPrefix("app.dayperk.documentation.") { return }

        if LocalPreviewMode.enabled && Bundle.main.bundleIdentifier != LocalPreviewMode.bundleIdentifier {
            // 防止误用正式应用标识构建演示版，必须在任何个人仓库读取前终止。
            NSApp.terminate(nil)
            return
        }

        let seedsPreview = LocalPreviewMode.enabled && LocalPreviewMode.requiresInitialSeed()
        if seedsPreview {
            do { try LocalPreviewMode.prepare(LocalPreviewMode.loadSeed()) }
            catch { NSAlert(error: error).runModal(); NSApp.terminate(nil); return }
        }
        statusBarController = StatusBarController()
        if LocalPreviewMode.enabled {
            do {
                let model = statusBarController!.model
                if seedsPreview { try LocalPreviewMode.apply(LocalPreviewMode.loadSeed(), to: model) }
                statusBarController?.showPopover = true
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
                NSApp.terminate(nil)
            }
            return
        }
        if LaunchAtLoginManager.shared.startsCaffeine {
            statusBarController?.model.tracking.setCaffeine(true)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // 已打开设置时保留原窗口，避免重新激活应用把设置换成菜单面板。
        if hasVisibleWindows {
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
            return true
        }
        // 菜单栏被挤出时，从应用程序重新打开仍可进入面板。
        statusBarController?.showPopover = true
        return true
    }

    func applicationWillTerminate(_: Notification) {
        statusBarController?.shutdown()
        _ = UserDataStore.shared.synchronize()
        LogService.info(L10n.text("ui.application_quit.0b009bfa"))
    }
}

// MARK: - App

@main
struct DayPerkApp: App {
    @ObservedObject private var language = LocalizationManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {}
            .commands {
                CommandMenu(L10n.text("ui.work_tracking.251d9be1")) {
                    Button(L10n.text("ui.open_menu_panel.e39e620f")) {
                        appDelegate.statusBarController?.showPopover = true
                    }
                    Button(L10n.text("ui.open_tracking_window.380761c8")) {
                        appDelegate.statusBarController?.showDashboardWindow()
                    }
                }
            }
    }
}
