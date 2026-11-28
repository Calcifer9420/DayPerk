// DayPerk，许可条款见仓库 LICENSE。
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrewButtonStyle: ButtonStyle {
    var prominent = false
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let compact = controlSize == .small || controlSize == .mini
        configuration.label.font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(configuration.role == .destructive ? Color.red : prominent ? Color.black : appearance.theme.color)
            .frame(minHeight: compact ? 16 : nil)
            .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 6 : 7)
            .background(appearance.theme.color.opacity(prominent ? 0.95 : configuration.isPressed ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(appearance.theme.color.opacity(prominent ? 0 : 0.25)))
            .contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
    }
}

struct BrewToggleStyle: ToggleStyle {
    var checkbox = false
    var showsLabel = true
    @ObservedObject private var appearance = AppearanceSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                if checkbox {
                    Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17)).foregroundStyle(configuration.isOn ? appearance.theme.color : .secondary)
                    if showsLabel { configuration.label }
                } else {
                    if showsLabel {
                        configuration.label
                        Spacer(minLength: 12)
                    }
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule().fill(configuration.isOn ? appearance.theme.color : Color.white.opacity(0.2))
                        Circle().fill(.white).padding(3)
                    }.frame(width: 44, height: 24)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? L10n.text("ui.on.8da97ddd") : L10n.text("ui.off.3fd47edc"))
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

struct CroppedBackgroundImage: View {
    let image: NSImage
    let crop: BackgroundCrop
    var body: some View {
        GeometryReader { geometry in
            let frame = crop.imageFrame(image: image.size, viewport: geometry.size)
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }.clipped().accessibilityHidden(true)
    }
}

struct BrewBackground: View {
    @ObservedObject var appearance: AppearanceSettings
    var panel = false
    var body: some View {
        ZStack {
            appearance.theme.canvas
            if appearance.background.enabled, let image = appearance.backgroundImage {
                CroppedBackgroundImage(image: image, crop: panel ? appearance.background.panelCrop : appearance.background.windowCrop)
                Color.black.opacity(appearance.background.dimming)
            } else {
                LinearGradient(colors: [appearance.theme.sidebar.opacity(0.6), .clear, appearance.theme.surface.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct BackgroundImageSettingsView: View {
    @ObservedObject var appearance: AppearanceSettings
    @State private var editing = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(L10n.text("ui.choose_background_image.1a250eda"), systemImage: "photo.badge.plus") { chooseImage() }
                InfoHelp(text: L10n.text("ui.settings_and_the_menu_panel_keep_se.3220adc7"))
                    .frame(width: 18, height: 18)
                if appearance.backgroundImage != nil {
                    Button(L10n.text("ui.adjust_visible_area.7424df57"), systemImage: "crop") { editing = true }
                        .labelStyle(.iconOnly).help(L10n.text("ui.adjust_visible_area.7424df57"))
                }
                Spacer()
                Toggle(L10n.text("ui.use_image_background.bf07114a"), isOn: Binding(get: { appearance.background.enabled }, set: {
                    var next = appearance.background; next.enabled = $0; appearance.updateBackground(next)
                })).disabled(appearance.backgroundImage == nil).fixedSize()
            }
            if let image = appearance.backgroundImage {
                HStack(spacing: 16) {
                    preview(image, title: L10n.text("ui.settings_window.fd768769"), panel: false, size: CGSize(width: 220, height: 166))
                    preview(image, title: L10n.text("ui.menu_bar_panel.abaa8536"), panel: true, size: CGSize(width: 127, height: 166))
                    Spacer()
                }
                HStack {
                    Text(L10n.text("ui.background_dimming.f4700509"))
                    Slider(value: Binding(get: { appearance.background.dimming }, set: {
                        var next = appearance.background; next.dimming = $0; appearance.updateBackground(next)
                    }), in: 0 ... 0.8)
                    Text("\(Int(appearance.background.dimming * 100))%").monospacedDigit().frame(width: 40)
                }
            }
        }
        .actionFeedback($error, isError: true)
        .sheet(isPresented: $editing) { BackgroundCropEditor(appearance: appearance) }
    }

    private func preview(_ image: NSImage, title: String, panel: Bool, size: CGSize) -> some View {
        VStack(spacing: 5) {
            CroppedBackgroundImage(image: image, crop: panel ? appearance.background.panelCrop : appearance.background.windowCrop)
                .frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseImage() {
        let picker = NSOpenPanel()
        picker.title = L10n.text("ui.choose_background_image.1a250eda")
        picker.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        picker.allowsMultipleSelection = false; picker.canChooseDirectories = false
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "DayPerk-preferences" && $0.isVisible }) else {
            error = L10n.text("ui.open_the_settings_window_first.c97f1aee"); return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        picker.beginSheetModal(for: window) { response in
            guard response == .OK, let url = picker.url else { return }
            do {
                try appearance.importBackground(from: url)
                error = ""
                DispatchQueue.main.async { editing = true }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct BackgroundCropEditor: View {
    @ObservedObject var appearance: AppearanceSettings
    @Environment(\.dismiss) private var dismiss
    @State private var panel = false
    @State private var draft: BackgroundPreferences
    @State private var dragStart: BackgroundCrop?

    init(appearance: AppearanceSettings, panel: Bool = false) {
        self.appearance = appearance
        _panel = State(initialValue: panel)
        _draft = State(initialValue: appearance.background)
    }

    private var crop: Binding<BackgroundCrop> {
        Binding(get: { panel ? draft.panelCrop : draft.windowCrop }, set: {
            if panel { draft.panelCrop = $0 } else { draft.windowCrop = $0 }
        })
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.text("ui.choose_the_visible_background_area.b40fd5f2")).font(.title2.weight(.semibold))
                Spacer()
                Picker(L10n.text("ui.preview_window.b9b25340"), selection: $panel) {
                    Text(L10n.text("ui.settings_window.fd768769")).tag(false); Text(L10n.text("ui.menu_bar_panel.abaa8536")).tag(true)
                }.pickerStyle(.segmented).frame(width: 240)
            }
            if let image = appearance.backgroundImage {
                let size = panel ? CGSize(width: 292, height: 380) : CGSize(width: 503, height: 380)
                CroppedBackgroundImage(image: image, crop: crop.wrappedValue)
                    .frame(width: size.width, height: size.height).contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { gesture in
                        let start = dragStart ?? crop.wrappedValue
                        dragStart = start
                        let frame = start.imageFrame(image: image.size, viewport: size)
                        var next = start
                        if frame.width > size.width { next.x -= gesture.translation.width / (frame.width - size.width) }
                        if frame.height > size.height { next.y -= gesture.translation.height / (frame.height - size.height) }
                        crop.wrappedValue = next.sanitized
                    }.onEnded { _ in dragStart = nil })
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(appearance.theme.color, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text(L10n.text("ui.zoom.b762aec7"))
                    Slider(value: crop.zoom, in: 1 ... 3).accessibilityLabel(L10n.text("ui.zoom.b762aec7"))
                    Text(String(format: "%.1f×", crop.wrappedValue.zoom)).monospacedDigit().frame(width: 42)
                }
                HStack {
                    Text(L10n.text("ui.horizontal_position.d4360b58"))
                    Slider(value: crop.x, in: 0 ... 1).accessibilityLabel(L10n.text("ui.horizontal_position.d4360b58"))
                    Text(L10n.text("ui.vertical_position.63e59c9a"))
                    Slider(value: crop.y, in: 0 ... 1).accessibilityLabel(L10n.text("ui.vertical_position.63e59c9a"))
                }
            }
            HStack {
                Button(L10n.text("ui.reset_to_center.83a47278")) { crop.wrappedValue = BackgroundCrop() }
                Spacer()
                Button(L10n.text("ui.cancel.2cd0f3be"), systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).help(L10n.text("ui.cancel.2cd0f3be")).keyboardShortcut(.cancelAction)
                Button(L10n.text("ui.apply_framing.d1665174"), systemImage: "checkmark") { appearance.updateBackground(draft); dismiss() }
                    .labelStyle(.iconOnly).help(L10n.text("ui.apply_framing.d1665174"))
                    .buttonStyle(BrewButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 650, height: 610)
            .preferredColorScheme(.dark).tint(appearance.theme.color).buttonStyle(BrewButtonStyle())
            .background(appearance.theme.canvas)
    }
}
