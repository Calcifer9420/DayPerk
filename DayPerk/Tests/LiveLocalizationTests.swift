import AppKit
import SwiftUI
import Testing
@testable import DayPerk

struct LiveLocalizationTests {
    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportLiveLanguageSwitchScreenshots() throws {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage
        manager.setLanguage(.english)
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        model.access.unlockAllData()
        try #require(!model.access.isDataLocked)
        defer { model.tracking.shutdown(); manager.setLanguage(original) }
        let host = NSHostingView(rootView: DayPerkPreferencesView(model: model, initialPage: .display))
        let size = NSSize(width: 980, height: 1000)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.alphaValue = 0; window.ignoresMouseEvents = true
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        window.appearance = NSAppearance(named: .darkAqua); window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPerkLiveLanguageReview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 同一个窗口连续切换，不能靠重新创建宿主绕过旧文案缓存。
        for language in [AppLanguage.english, .french, .german, .traditionalChinese, .japanese, .korean, .chinese] {
            manager.setLanguage(language)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25)); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(language.rawValue + ".png"))
        }
    }

}
