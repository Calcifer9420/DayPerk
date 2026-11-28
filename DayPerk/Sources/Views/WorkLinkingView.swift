import SwiftUI

/// 联动规则独立于作息编辑，沿用同一份已校验配置。
struct WorkLinkingView: View {
    @Binding var config: DayPerkConfiguration
    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    var body: some View {
        Form {
            Section(L10n.text("ui.startup_caffeine.14973437")) {
                option(L10n.text("ui.launch_at_login_and_enable_caffeine.98f9ce2f"), value: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }),
                       help: L10n.text("ui.launch_dayperk_with_caffeine_when_y.98809a7a"))
                if launchAtLogin.needsApproval {
                    Button(L10n.text("ui.allow_in_system_login_items.0e92ee08")) { launchAtLogin.openSystemSettings() }
                }
            }

            automationSections
        }.formStyle(.grouped)
            .onChange(of: launchAtLogin.errorMessage) { _, text in ActionToastCenter.shared.show(text, isError: true) }
            .onAppear { launchAtLogin.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in launchAtLogin.refreshStatus() }
    }

    var automationSections: some View {
        Group {
            Section(L10n.text("ui.caffeine_and_tracking.3a31e90a")) {
                option(L10n.text("ui.enable_caffeine_linking.d442861e"), value: $config.linkCaffeine,
                       help: L10n.text("ui.control_caffeine_to_tracking_linkin.5195fb40"))
                Group {
                    option(L10n.text("ui.start_tracking_when_caffeine_turns.e1db1756"), value: $config.automation.caffeineStartsWork,
                           help: L10n.text("ui.applies_only_on_workdays_or_registe.7b5d5b50"))
                    option(L10n.text("ui.extend_the_linking_window_by_thirty.b4c8c769"), value: $config.automation.caffeineBuffer,
                           help: L10n.text("ui.extend_the_linking_window_to_thirty.f479db67"))
                    option(L10n.text("ui.pause_when_caffeine_turns_off_outsi.fd0e9bc5"), value: $config.automation.caffeineStopsWork,
                           help: L10n.text("ui.applies_only_on_workdays_or_registe.cbbd92b0"))
                }.disabled(!config.linkCaffeine)
            }
            Section(L10n.text("ui.data_locking_and_system_events.f5151a11")) {
                option(L10n.text("ui.pause_on_data_lock_near_a_break_sta.3e7de311"), value: $config.automation.lockPausesWork,
                       help: L10n.text("ui.check_when_lock_all_is_clicked_or_t.56c99d92"))
                option(L10n.text("ui.start_on_data_unlock_near_a_break_e.b9c804a1"), value: $config.automation.unlockStartsWork,
                       help: L10n.text("ui.check_only_after_successful_unlock.6888d52f"))
                option(L10n.text("ui.pause_on_screen_lock_display_sleep.f3dedfeb"), value: $config.automation.pauseOnSystemLock,
                       help: L10n.text("ui.pause_on_system_lock_or_sleep_notif.c0f9ee2a"))
                option(L10n.text("ui.disable_caffeine_on_screen_lock_or.52dff059"), value: $config.automation.caffeineOffOnSystemLock,
                       help: L10n.text("ui.release_the_wake_assertion_on_syste.f5111175"))
            }
            Section(L10n.text("ui.accidental_tap_protection.2367f5df")) {
                HStack(spacing: 6) {
                    Text(L10n.text("automation.seconds"))
                    InfoHelp(text: L10n.text("automation.seconds_help")).frame(width: 18, height: 18)
                    Spacer()
                    TextField(L10n.text("automation.seconds"), value: Binding(get: { config.automation.tapProtectionSeconds ?? 10 }, set: { config.automation.tapProtectionSeconds = $0 }), format: .number.grouping(.never))
                        .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80)
                    Text(L10n.text("automation.seconds_unit"))
                }
                option(L10n.text("ui.discard_sessions_stopped_within_ten.2cfa4ab1"), value: $config.automation.discardShortSessions,
                       help: L10n.text("ui.remove_only_the_short_session_and_i.5ddc0695"))
                option(L10n.text("ui.count_pauses_resumed_within_ten_sec.e8e13e4d"), value: $config.automation.bridgeShortPauses,
                       help: L10n.text("automation.resume_help"))
            }
        }
    }

    private func option(_ title: String, value: Binding<Bool>, help: String) -> some View {
        HStack {
            Text(title)
            InfoHelp(text: help).frame(width: 18, height: 18)
            Spacer()
            Toggle(title, isOn: value).labelsHidden().toggleStyle(BrewToggleStyle(checkbox: true, showsLabel: false)).accessibilityLabel(title)
        }
    }
}
