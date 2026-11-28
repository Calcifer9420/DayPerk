import AppKit
import ImageIO
import SwiftUI

enum BrewTheme: String, CaseIterable, Identifiable {
    case cyan = "晴空青", blue = "湖水蓝", indigo = "靛蓝", purple = "鸢尾紫"
    case rose = "玫瑰粉", red = "珊瑚红", orange = "暖橘", amber = "琥珀金"
    case green = "森林绿", mint = "薄荷绿", teal = "深海青", graphite = "石墨灰"
    var id: String {
        rawValue
    }

    var nsColor: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .cyan: rgb = (0.20, 0.82, 0.96)
        case .blue: rgb = (0.32, 0.65, 1)
        case .indigo: rgb = (0.55, 0.57, 1)
        case .purple: rgb = (0.76, 0.55, 1)
        case .rose: rgb = (1, 0.54, 0.73)
        case .red: rgb = (1, 0.48, 0.45)
        case .orange: rgb = (1, 0.65, 0.32)
        case .amber: rgb = (0.98, 0.80, 0.35)
        case .green: rgb = (0.40, 0.82, 0.48)
        case .mint: rgb = (0.37, 0.89, 0.70)
        case .teal: rgb = (0.26, 0.75, 0.74)
        case .graphite: rgb = (0.72, 0.76, 0.82)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var canvasNSColor: NSColor { nsColor.blended(withFraction: 0.86, of: .black)! }
    var canvas: Color { Color(nsColor: canvasNSColor) }
    var surface: Color { Color(nsColor: nsColor.blended(withFraction: 0.81, of: .black)!) }
    var sidebar: Color { Color(nsColor: nsColor.blended(withFraction: 0.76, of: .black)!) }
}

final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    @Published private(set) var theme: BrewTheme
    @Published private(set) var backgroundImage: NSImage?
    @Published private(set) var background: BackgroundPreferences
    private let defaults: any UserDataPreferences
    private let imageURL: URL
    init(defaults: any UserDataPreferences = UserDataStore.shared, imageURL: URL? = nil) {
        self.defaults = defaults
        self.imageURL = imageURL ?? UserDataStore.directory.appendingPathComponent("Appearance/background.png")
        theme = defaults.string(forKey: "brewTheme").flatMap(BrewTheme.init(rawValue:)) ?? .cyan
        background = defaults.data(forKey: "brewBackground").flatMap { try? JSONDecoder().decode(BackgroundPreferences.self, from: $0) } ?? BackgroundPreferences()
        backgroundImage = NSImage(contentsOf: self.imageURL)
    }

    func reloadFromStorage() {
        let value = AppearanceSettings(defaults: defaults, imageURL: imageURL)
        theme = value.theme; background = value.background; backgroundImage = value.backgroundImage
    }

    func select(_ theme: BrewTheme) {
        self.theme = theme
        defaults.set(theme.rawValue, forKey: "brewTheme")
    }

    func updateBackground(_ value: BackgroundPreferences) {
        var safe = value
        safe.windowCrop = safe.windowCrop.sanitized
        safe.panelCrop = safe.panelCrop.sanitized
        safe.dimming = safe.dimming.isFinite ? min(0.8, max(0, safe.dimming)) : 0.3
        background = safe
        defaults.set(try? JSONEncoder().encode(safe), forKey: "brewBackground")
    }

    func resetToDefaults() throws {
        if FileManager.default.fileExists(atPath: imageURL.path) {
            let backup = imageURL.deletingLastPathComponent().appendingPathComponent("background-before-reset-" + UUID().uuidString + ".png")
            try FileManager.default.moveItem(at: imageURL, to: backup)
        }
        backgroundImage = nil
        select(.cyan)
        updateBackground(BackgroundPreferences())
    }

    /// 只保留缩小后的本机副本，不持久保存来源路径，也不把图片加入源码资源。
    func importBackground(from url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (attributes.fileSize ?? 0) <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 4096,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw DayPerkInputError(message: L10n.text("ui.choose_a_valid_image_no_larger_than.662eb97d")) }
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: imageURL.path) {
            // 替换前保留上一张背景，不改动用户选择的原图。
            let backup = imageURL.deletingPathExtension().appendingPathExtension("backup.png")
            try Data(contentsOf: imageURL).write(to: backup, options: .atomic)
        }
        try data.write(to: imageURL, options: .atomic)
        backgroundImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        var next = background
        next.enabled = true; next.windowCrop = BackgroundCrop(); next.panelCrop = BackgroundCrop()
        updateBackground(next)
    }
}

struct BackgroundCrop: Codable, Equatable {
    var x: Double = 0.5
    var y: Double = 0.5
    var zoom: Double = 1

    var sanitized: Self {
        Self(x: x.isFinite ? min(1, max(0, x)) : 0.5,
             y: y.isFinite ? min(1, max(0, y)) : 0.5,
             zoom: zoom.isFinite ? min(3, max(1, zoom)) : 1)
    }

    func imageFrame(image: CGSize, viewport: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let crop = sanitized
        let scale = max(viewport.width / image.width, viewport.height / image.height) * crop.zoom
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) * crop.x, y: (viewport.height - size.height) * crop.y, width: size.width, height: size.height)
    }
}

struct BackgroundPreferences: Codable, Equatable {
    var enabled = false
    var dimming: Double = 0.3
    var windowCrop = BackgroundCrop()
    var panelCrop = BackgroundCrop()
}
