import AppKit
import SwiftUI

struct ActionToast: Identifiable {
    let id = UUID()
    var text: String
    var isError: Bool
}

@MainActor final class ActionToastCenter: ObservableObject {
    static let shared = ActionToastCenter()
    @Published private(set) var current: ActionToast?

    func show(_ text: String, isError: Bool = false) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        current = ActionToast(text: L10n.text(text), isError: isError)
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
    }
}

private struct ActionFeedback: ViewModifier {
    @Binding var message: String
    var isError: Bool
    func body(content: Content) -> some View {
        content.onChange(of: message) { _, text in
            guard !text.isEmpty else { return }
            ActionToastCenter.shared.show(text, isError: isError)
            // 清空后再次点击同一个按钮也会重新提示。
            message = ""
        }
    }
}

private struct ActionToastHost: ViewModifier {
    @ObservedObject private var center = ActionToastCenter.shared
    @ObservedObject private var appearance = AppearanceSettings.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            ZStack {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Color.red : Color.green)
                    Text(toast.text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                }.font(.callout.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(appearance.theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
                    .transformAnchorPreference(key: PanelAreaAnchors.self, value: .bounds) { value, anchor in value["action-toast"] = anchor }
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 18)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("action-toast")
                    .onTapGesture { center.dismiss(id: toast.id) }
                    .transition(.opacity)
                    .task(id: toast.id) {
                        if let window = NSApp.keyWindow {
                            NSAccessibility.post(element: window, notification: .announcementRequested,
                                userInfo: [.announcement: toast.text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                        }
                        do { try await Task.sleep(for: .seconds(toast.isError ? 5 : 3)) }
                        catch { return }
                        center.dismiss(id: toast.id)
                    }
            }
            }.animation(.easeOut(duration: 0.18), value: center.current?.id)
        }
    }
}

extension View {
    func actionFeedback(_ message: Binding<String>, isError: Bool = false) -> some View {
        modifier(ActionFeedback(message: message, isError: isError))
    }
    func actionToastHost() -> some View { modifier(ActionToastHost()) }
}
