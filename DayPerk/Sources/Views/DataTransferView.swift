import SwiftUI
import UniformTypeIdentifiers

struct DataTransferView: View {
    @ObservedObject var model: DayPerkModel
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var pendingImport: AppDataArchive?
    @State private var confirmingImport = false
    @State private var message = ""
    @State private var isError = false
    private var allowed: Bool { model.access.settingsUnlocked && !model.access.isDataLocked }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L10n.text("backup.overview")).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    transferCard("backup.export", detail: "backup.export_detail", symbol: "square.and.arrow.up") {
                        model.access.authorizeDataTransfer(exportBackup)
                    }
                    transferCard("backup.import", detail: "backup.import_detail", symbol: "square.and.arrow.down") {
                        model.access.authorizeDataTransfer(selectImport)
                    }
                }.fixedSize(horizontal: false, vertical: true).disabled(model.access.isAuthenticating)
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(appearance.theme.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("backup.local_folder")).font(.headline)
                        Text(L10n.text("backup.local_detail")).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("backup.open_folder")) { NSWorkspace.shared.open(UserDataStore.directory) }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(appearance.theme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(24)
        }
        .actionFeedback($message, isError: isError)
        .alert(L10n.text("backup.confirm_title"), isPresented: $confirmingImport) {
            Button(L10n.text("ui.cancel.2cd0f3be"), role: .cancel) { pendingImport = nil }
            Button(L10n.text("backup.restore"), role: .destructive) {
                guard allowed, let archive = pendingImport else { pendingImport = nil; return }
                do {
                    guard let restore = model.restoreBackup else { throw DayPerkInputError(message: L10n.text("backup.unavailable")) }
                    try restore(archive)
                } catch { message = error.localizedDescription; isError = true }
                pendingImport = nil
            }
        } message: {
            Text(L10n.format("backup.confirm_message", pendingImport?.createdAt.formatted(.dateTime.locale(LocalizationManager.shared.currentLocale)) ?? ""))
        }
    }
    private func transferCard(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(appearance.theme.color)
            Text(L10n.text(detail)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Button(L10n.text(title), action: action)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(appearance.theme.sidebar.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
    private func exportBackup() {
        guard allowed else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DayPerk-" + WorkPlan.dayKey(Date(), calendar: model.workCalendar) + ".dayperk.json"
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "DayPerk-preferences" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, allowed else { return }
            do {
                model.tracking.checkpoint()
                model.workStatus.checkpoint()
                LaunchAtLoginManager.shared.checkpoint()
                let archive = try AppDataBackup.create()
                try AppDataBackup.encoded(archive).write(to: url, options: .atomic)
                message = L10n.text("backup.exported"); isError = false
            } catch { message = error.localizedDescription; isError = true }
        }
    }
    private func selectImport() {
        guard allowed else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.allowedContentTypes = [.data]
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "DayPerk-preferences" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, allowed else { return }
            do { pendingImport = try AppDataBackup.read(url); confirmingImport = true; isError = false }
            catch { message = error.localizedDescription; isError = true }
        }
    }
}
