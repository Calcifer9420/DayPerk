// DayPerk，许可条款见仓库 LICENSE。
import ServiceManagement
import SwiftUI

@MainActor final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage = ""
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let defaults: any UserDataPreferences

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        self.readStatus = readStatus; self.register = register; self.unregister = unregister
        status = readStatus()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var startsCaffeine: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        errorMessage = ""
        do {
            if enabled { try register() } else { try unregister() }
            defaults.set(enabled, forKey: "launchAtLoginEnabled")
        } catch {
            errorMessage = L10n.text("ui.unable_to_update_launch_at_login_ch.c85f8aa0")
        }
        refreshStatus()
    }

    func refreshStatus() { status = readStatus() }
    func checkpoint() { defaults.set(isEnabled, forKey: "launchAtLoginEnabled") }
    func restoreSavedPreference() {
        guard let enabled = defaults.object(forKey: "launchAtLoginEnabled") as? Bool, enabled != isEnabled else { return }
        setEnabled(enabled)
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
