// DayPerk，许可条款见仓库 LICENSE。
import Foundation
import LocalAuthentication
import SwiftUI

/// 仅保存显示和有效期偏好；验证结果只驻留内存，不保存或接触系统密码。
final class SalaryAccessController: ObservableObject {
    static let durationKey = "salaryAuthorizationSeconds"
    static let maximumDuration = 9999 * 3600 + 3599
    @Published private(set) var authorizationDuration: Int
    @Published private(set) var dashboardProtected: Bool
    @Published private(set) var hideWhenPaused: Bool
    @Published private(set) var authenticatedUntil: Date?
    @Published private(set) var isDataLocked: Bool
    private let now: () -> Date
    private var expiryTimer: Timer?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authenticationMessage = ""
    private let defaults: any UserDataPreferences
    private let allowsInitialSetup: Bool
    private let authenticate: ((String, @escaping (Bool) -> Void) -> Void)?
    private var context: LAContext?
    private var generation = 0
    private var authenticationInteractionUntil: Date?
    var authenticationWillBegin: (() -> Void)?
    var authenticationDidFinish: (() -> Void)?
    var dataWillLock: (() -> Void)?
    var sensitiveInformationWillHide: (() -> Void)?
    var dataDidUnlock: (() -> Void)?

    var isHandlingSystemAuthentication: Bool {
        isAuthenticating || (authenticationInteractionUntil.map { now() < $0 } ?? false)
    }

    init(defaults: any UserDataPreferences = UserDataStore.shared, now: @escaping () -> Date = Date.init, allowsInitialSetup: Bool = false, authenticate: ((String, @escaping (Bool) -> Void) -> Void)? = nil) {
        self.defaults = defaults
        self.allowsInitialSetup = allowsInitialSetup
        self.now = now
        self.authenticate = authenticate
        let duration = defaults.object(forKey: Self.durationKey) as? Int ?? 600
        authorizationDuration = (0 ... Self.maximumDuration).contains(duration) ? duration : 600
        isDataLocked = defaults.bool(forKey: "allDataLocked")
        dashboardProtected = defaults.object(forKey: "salaryDashboardProtected") as? Bool ?? true
        hideWhenPaused = defaults.object(forKey: "hideAmountWhenPaused") as? Bool ?? true
        if allowsInitialSetup, !SalaryDataPresence.requiresProtection(defaults: defaults) {
            isDataLocked = false
            if defaults.bool(forKey: "allDataLocked") { defaults.set(false, forKey: "allDataLocked") }
            authenticatedUntil = .distantFuture
        }
    }

    var settingsUnlocked: Bool {
        !isDataLocked && (authenticatedUntil.map { now() < $0 } ?? false)
    }

    var canViewIncomeDetails: Bool {
        !isDataLocked && (!dashboardProtected || settingsUnlocked)
    }

    deinit { expiryTimer?.invalidate() }

    static func parseDuration(_ text: String) throws -> Int {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2]),
              (0 ... 9999).contains(hours), (0 ... 59).contains(minutes), (0 ... 59).contains(seconds),
              hours + minutes + seconds > 0 else { throw invalidDuration() }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func invalidDuration() -> DayPerkInputError {
        DayPerkInputError(message: L10n.text("authorization.invalid_duration"))
    }

    func setAuthorizationDuration(_ seconds: Int) throws {
        guard (0 ... Self.maximumDuration).contains(seconds) else { throw Self.invalidDuration() }
        try defaults.persist([Self.durationKey: seconds])
        authorizationDuration = seconds
    }

    func handleSystemInterruption() {
        // 手动锁定模式不因息屏或睡眠提前撤回，限时授权仍沿用系统中断保护。
        if authenticatedUntil != .distantFuture { lockAll() }
    }

    func setHideWhenPaused(_ value: Bool) {
        if value {
            if isAuthenticating { lockAll() }
            authenticationMessage = ""
            hideWhenPaused = true
            defaults.set(true, forKey: "hideAmountWhenPaused")
        } else if hideWhenPaused {
            verify(L10n.text("ui.show_menu_bar_amount_while_paused.e590f123")) {
                self.hideWhenPaused = false
                self.defaults.set(false, forKey: "hideAmountWhenPaused")
            }
        }
    }

    func setSensitiveInformationHidden(_ hidden: Bool, privacy: PrivacySettings) {
        if hidden {
            sensitiveInformationWillHide?()
            if isAuthenticating { lockAll() }
            authenticationMessage = ""
            privacy.hideSensitiveInformation()
        } else if privacy.isPrivacyModeEnabled {
            verify(L10n.text("ui.show_sensitive.43068b4c")) {
                privacy.revealSensitiveInformation()
            }
        }
    }

    func unlockIncomeDetails() {
        if isDataLocked {
            unlockAllData(); return
        }
        guard !canViewIncomeDetails else { return }
        verify(L10n.text("ui.unlock_dayperk_income_breakdown.99983280")) {}
    }

    func unlockSettings() {
        if isDataLocked {
            unlockAllData(); return
        }
        guard !settingsUnlocked else { return }
        verify(L10n.text("ui.view_or_edit_personal_pay_data.4bed4781")) {}
    }

    func authorizeDataTransfer(_ perform: @escaping () -> Void) {
        guard !isDataLocked else { return }
        if settingsUnlocked { perform(); return }
        verify(L10n.text("backup.authenticate")) {
            guard self.settingsUnlocked else { return }
            perform()
        }
    }

    func setDashboardProtected(_ value: Bool) {
        if value {
            if isAuthenticating { lockAll() }
            dashboardProtected = true
            defaults.set(true, forKey: "salaryDashboardProtected")
        } else if dashboardProtected {
            // 关闭保护始终重新验证，不能复用已打开页面的解锁状态。
            verify(L10n.text("ui.turn_off_authentication_protection.b7092b4e")) {
                self.dashboardProtected = false
                self.defaults.set(false, forKey: "salaryDashboardProtected")
            }
        }
    }

    func lockAll() {
        generation += 1
        context?.invalidate(); context = nil
        isAuthenticating = false
        authenticationInteractionUntil = nil
        authenticatedUntil = nil
        expiryTimer?.invalidate(); expiryTimer = nil
    }

    func revokeAuthorization() {
        lockAll()
    }

    func resetDisplayPreferences(privacy: PrivacySettings, reset: @escaping () throws -> Void, completion: @escaping (Error?) -> Void) {
        let apply = {
            do {
                try reset()
                try self.setAuthorizationDuration(600)
                self.dashboardProtected = true; self.hideWhenPaused = true
                self.defaults.set(true, forKey: "salaryDashboardProtected")
                self.defaults.set(true, forKey: "hideAmountWhenPaused")
                privacy.revealSensitiveInformation()
                self.defaults.set(false, forKey: "isMenuBarAmountHidden")
                self.revokeAuthorization()
                completion(nil)
            } catch { completion(error) }
        }
        // 重置也不能绕过“展示敏感信息”的验证要求。
        if privacy.isPrivacyModeEnabled { verify(L10n.text("display.reset_auth"), success: apply) }
        else { apply() }
    }

    func lockAllData() {
        dataWillLock?()
        lockAll()
        isDataLocked = true
        defaults.set(true, forKey: "allDataLocked")
    }

    func unlockAllData() {
        guard isDataLocked else { return }
        verify(L10n.text("ui.unlock_all_dayperk_data.d82d2649")) {
            self.isDataLocked = false
            self.defaults.set(false, forKey: "allDataLocked")
            self.dataDidUnlock?()
        }
    }

    private func verify(_ reason: String, success: @escaping () -> Void) {
        guard !isAuthenticating else { return }
        if allowsInitialSetup, !SalaryDataPresence.requiresProtection(defaults: defaults) {
            authenticatedUntil = .distantFuture
            success()
            return
        }
        generation += 1
        let request = generation
        let duration = authorizationDuration
        isAuthenticating = true
        authenticationWillBegin?()
        authenticationMessage = ""
        let complete: (Bool) -> Void = { [weak self] granted in
            let finish = {
                guard let self, self.generation == request else { return }
                self.context = nil
                if granted {
                    self.authenticatedUntil = duration == 0 ? .distantFuture : self.now().addingTimeInterval(Double(duration))
                    self.expiryTimer?.invalidate()
                    self.expiryTimer = nil
                    if duration > 0 {
                        let timer = Timer(timeInterval: Double(duration), repeats: false) { [weak self] _ in self?.lockAll() }
                        self.expiryTimer = timer
                        RunLoop.main.add(timer, forMode: .common)
                    }
                    success()
                } else {
                    self.authenticationMessage = L10n.text("ui.not_unlocked_please_try_again.1c83719a")
                }
                // 系统验证结束会异步交还焦点；避免迟到的失焦事件收起原界面。
                self.authenticationInteractionUntil = self.now().addingTimeInterval(1)
                self.authenticationDidFinish?()
                self.isAuthenticating = false
            }
            if Thread.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
        if let authenticate {
            authenticate(reason, complete); return
        }
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { complete(false); return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L10n.text(reason)) { granted, _ in complete(granted) }
    }
}

final class PrivacySettings: ObservableObject {
    private let defaults: any UserDataPreferences
    @Published var isStatisticsShowcaseEnabled: Bool {
        didSet { defaults.set(isStatisticsShowcaseEnabled, forKey: "statisticsShowcaseEnabled") }
    }
    @Published private(set) var isPrivacyModeEnabled: Bool {
        didSet { defaults.set(isPrivacyModeEnabled, forKey: "isPrivacyModeEnabled") }
    }

    fileprivate func hideSensitiveInformation() { isPrivacyModeEnabled = true }
    fileprivate func revealSensitiveInformation() { isPrivacyModeEnabled = false }

    init(defaults: any UserDataPreferences = UserDataStore.shared) {
        self.defaults = defaults
        isStatisticsShowcaseEnabled = defaults.bool(forKey: "statisticsShowcaseEnabled")
        let legacyHidden = defaults.bool(forKey: "isMenuBarAmountHidden")
        isPrivacyModeEnabled = defaults.bool(forKey: "isPrivacyModeEnabled") || legacyHidden
        if legacyHidden {
            defaults.set(true, forKey: "isPrivacyModeEnabled")
            defaults.set(false, forKey: "isMenuBarAmountHidden")
        }
    }
}
