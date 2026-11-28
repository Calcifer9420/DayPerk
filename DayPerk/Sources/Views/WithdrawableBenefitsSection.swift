import SwiftUI

/// 各地区共用额外收入编辑器，可登记补贴等收入；缴费仍由薪酬模块独立计算。
struct WithdrawableBenefitsSection: View {
    @ObservedObject var model: DayPerkModel
    var region: PayrollRegion
    var currency: String
    @State private var editing: WithdrawableBenefit?
    @State private var amount = ""

    private var values: [WithdrawableBenefit] { model.withdrawableBenefits(region: region, currency: currency) }
    private var canEdit: Bool { model.access.settingsUnlocked && !model.privacy.isPrivacyModeEnabled }
    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: currency).locale(LocalizationManager.shared.currentLocale))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if values.isEmpty && editing == nil { Text(L10n.text("benefits.empty")).foregroundStyle(.secondary) }
                ForEach(values) { item in
                    if editing?.id == item.id { editor }
                    else { row(item) }
                    Divider()
                }
                if let editing, !values.contains(where: { $0.id == editing.id }) { editor; Divider() }
            }
        } header: {
            HStack(spacing: 8) {
                Text(L10n.text("benefits.title"))
                InfoHelp(text: L10n.text("benefits.help")).frame(width: 18, height: 18)
                Spacer()
                Button(L10n.text("benefits.add"), systemImage: "plus") {
                    beginEditing(WithdrawableBenefit())
                }.labelStyle(.iconOnly).help(L10n.text("benefits.add")).disabled(editing != nil || !canEdit)
            }
        }
        .onChange(of: canEdit) { _, allowed in if !allowed { editing = nil } }
    }

    private func row(_ item: WithdrawableBenefit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(item.displayName).fontWeight(.medium)
                Spacer()
                Text(money(item.monthlyAmount)).monospacedDigit()
                Button(L10n.text("ui.edit.05183656"), systemImage: "square.and.pencil") { beginEditing(item) }
                    .labelStyle(.iconOnly).help(L10n.text("ui.edit.05183656"))
                deleteButton(item)
            }
            selections(item)
        }.disabled(!canEdit)
    }

    private func selections(_ item: WithdrawableBenefit) -> some View {
        HStack(spacing: 22) {
            Toggle(L10n.text("benefits.in_rate"), isOn: Binding(get: { item.includeInRate }, set: { flag in
                var value = item; value.includeInRate = flag; save(value)
            }))
            Toggle(L10n.text("benefits.in_estimate"), isOn: Binding(get: { item.showInEstimate }, set: { flag in
                var value = item; value.showInEstimate = flag; save(value)
            }))
            Spacer(minLength: 0)
        }.toggleStyle(BrewToggleStyle(checkbox: true)).font(.callout)
    }

    @ViewBuilder private var editor: some View {
        if let item = editing {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(L10n.text("ui.benefit_name.e09d68c7"),
                        text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
                        .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(L10n.text("ui.benefit_name.e09d68c7"))
                    TextField("0", text: $amount).labelsHidden()
                        .multilineTextAlignment(.trailing).frame(width: 135).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("ui.monthly_withdrawable_amount_after_t.b4e7ed3b"))
                    Text(currency + "/" + L10n.text("month")).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Toggle(L10n.text("benefits.in_rate"), isOn: Binding(get: { editing?.includeInRate ?? true }, set: { editing?.includeInRate = $0 }))
                    Toggle(L10n.text("benefits.in_estimate"), isOn: Binding(get: { editing?.showInEstimate ?? true }, set: { editing?.showInEstimate = $0 }))
                    Spacer(minLength: 0)
                    if values.contains(where: { $0.id == item.id }) { deleteButton(item) }
                    Button(L10n.text("ui.cancel.2cd0f3be"), systemImage: "xmark") { editing = nil }.labelStyle(.iconOnly)
                        .help(L10n.text("ui.cancel.2cd0f3be"))
                    Button(L10n.text("benefits.save"), systemImage: "checkmark") { save(editing, finishEditing: true) }
                        .labelStyle(.iconOnly).buttonStyle(BrewButtonStyle(prominent: true)).help(L10n.text("benefits.save"))
                }.toggleStyle(BrewToggleStyle(checkbox: true)).font(.callout)
            }.padding(12).background(model.appearance.theme.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .disabled(!canEdit)
        }
    }

    private func deleteButton(_ item: WithdrawableBenefit) -> some View {
        Button(L10n.text("ui.remove.c3812fc4"), systemImage: "trash", role: .destructive) {
            persist(values.filter { $0.id != item.id }, finishEditing: editing?.id == item.id)
        }.labelStyle(.iconOnly).help(L10n.text("ui.remove.c3812fc4"))
    }
    private func save(_ item: WithdrawableBenefit?, finishEditing: Bool = false) {
        guard var item else { return }
        if finishEditing {
            guard let number = LocalizedNumberInput.value(amount, locale: LocalizationManager.shared.currentLocale),
                  number >= 0, !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                ActionToastCenter.shared.show(L10n.text("ui.enter_a_benefit_name_and_a_valid_no.cef26c0d"), isError: true)
                return
            }
            item.monthlyAmount = number
        }
        var updated = values
        if let index = updated.firstIndex(where: { $0.id == item.id }) { updated[index] = item }
        else { updated.append(item) }
        persist(updated, finishEditing: finishEditing)
    }
    private func beginEditing(_ item: WithdrawableBenefit) {
        amount = item.monthlyAmount.formatted(.number.locale(LocalizationManager.shared.currentLocale).grouping(.never).precision(.fractionLength(0 ... 2)))
        editing = item
    }
    private func persist(_ updated: [WithdrawableBenefit], finishEditing: Bool) {
        guard canEdit else { return }
        do {
            try model.saveBenefits(updated, region: region, currency: currency)
            if finishEditing { editing = nil }
            ActionToastCenter.shared.show(L10n.text("benefits.saved"))
        } catch { ActionToastCenter.shared.show(error.localizedDescription, isError: true) }
    }
}
