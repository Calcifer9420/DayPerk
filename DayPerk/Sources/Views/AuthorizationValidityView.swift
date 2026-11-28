import SwiftUI

/// 验证有效期是全局偏好，保存设置不会延长已经打开的授权。
struct AuthorizationValidityView: View {
    @ObservedObject var access: SalaryAccessController
    @State private var untilManualLock: Bool
    @State private var duration: String

    init(access: SalaryAccessController) {
        self.access = access
        _untilManualLock = State(initialValue: access.authorizationDuration == 0)
        _duration = State(initialValue: WorkDurationInput.formatSeconds(access.authorizationDuration > 0 ? access.authorizationDuration : 600))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.text("authorization.validity"))
            InfoHelp(text: L10n.text("authorization.help")).frame(width: 18, height: 18)
            Spacer()
            Picker(L10n.text("authorization.validity"), selection: $untilManualLock) {
                Text(L10n.text("authorization.timed")).tag(false)
                Text(L10n.text("authorization.manual")).tag(true)
            }.labelsHidden().fixedSize()
        }
        HStack {
            if untilManualLock {
                Text(L10n.text("authorization.manual_detail")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(L10n.text("authorization.duration"))
                Spacer()
                TextField("00:10:00", text: $duration).labelsHidden().textFieldStyle(.roundedBorder)
                    .monospacedDigit().multilineTextAlignment(.trailing).frame(width: 150)
                    .accessibilityLabel(L10n.text("authorization.duration"))
            }
            Button(L10n.text("authorization.save"), systemImage: "checkmark") {
                do {
                    try access.setAuthorizationDuration(untilManualLock ? 0 : SalaryAccessController.parseDuration(duration))
                    if !untilManualLock { duration = WorkDurationInput.formatSeconds(access.authorizationDuration) }
                    ActionToastCenter.shared.show(L10n.text("authorization.saved"))
                } catch { ActionToastCenter.shared.show(error.localizedDescription, isError: true) }
            }.labelStyle(.iconOnly).help(L10n.text("authorization.save"))
                .buttonStyle(BrewButtonStyle(prominent: true)).disabled(access.isAuthenticating)
        }
        .onChange(of: access.authorizationDuration) { _, seconds in
            untilManualLock = seconds == 0
            duration = WorkDurationInput.formatSeconds(seconds > 0 ? seconds : 600)
        }
    }
}
