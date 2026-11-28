import AppKit
import SwiftUI

struct StatusColorSample: View {
    var color: Color
    @ObservedObject private var appearance = AppearanceSettings.shared
    var body: some View {
        RoundedRectangle(cornerRadius: 5).fill(color)
            .background(appearance.theme.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.6), lineWidth: 1))
    }
}

struct StatusColorPalette: View {
    @Binding var color: Color
    var close: () -> Void
    @Environment(\.locale) private var locale
    @State private var hue = 0.5
    @State private var saturation = 1.0
    @State private var brightness = 1.0
    @State private var opacity = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("workstatus.color")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("ui.cancel.2cd0f3be"))
            }
            StatusColorSample(color: color).frame(height: 30)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(BrewTheme.allCases) { theme in
                    Button {
                        load(theme.color, preservingOpacity: true); updateColor()
                    } label: {
                        Circle().fill(theme.color).frame(width: 26, height: 26)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.text(theme.rawValue))
                }
            }
            component("workstatus.color_hue", value: $hue, tint: Color(hue: hue, saturation: 1, brightness: 1))
            component("workstatus.color_saturation", value: $saturation, tint: .accentColor)
            component("workstatus.color_brightness", value: $brightness, tint: .accentColor)
            component("workstatus.color_opacity", value: $opacity, tint: .accentColor)
        }.padding(16).frame(width: 270).preferredColorScheme(.dark)
            .onAppear { load(color) }
            .onChange(of: hue) { _, _ in updateColor() }
            .onChange(of: saturation) { _, _ in updateColor() }
            .onChange(of: brightness) { _, _ in updateColor() }
            .onChange(of: opacity) { _, _ in updateColor() }
    }

    private func component(_ key: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(L10n.text(key)).font(.callout).frame(width: 64, alignment: .leading)
            Slider(value: value, in: 0 ... 1).tint(tint).accessibilityLabel(L10n.text(key))
            Text(value.wrappedValue.formatted(.percent.locale(locale).precision(.fractionLength(0))))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
    }

    private func load(_ color: Color, preservingOpacity: Bool = false) {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return }
        hue = value.hueComponent; saturation = value.saturationComponent; brightness = value.brightnessComponent
        if !preservingOpacity { opacity = value.alphaComponent }
    }

    private func updateColor() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
    }
}
