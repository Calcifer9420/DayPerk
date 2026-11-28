import AppKit
import CoreImage
import SwiftUI
import Testing
import WebKit
@testable import DayPerk

/// README 复用真实面板和随应用分发的动画，只在独立文档沙盒中导出。
struct DocumentationPaydayDemoTests {
    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func exportBilingualPaydayDemo() async throws {
        try DocumentationScreenshotTests().exportReadmeDetails()
        for language in ["zh-Hans", "en"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPerkReadmeScreens-" + Bundle.main.bundleIdentifier! + "-" + language)
            let base = try #require(NSImage(contentsOf: directory.appendingPathComponent("payday-before.png")))
            let size = NSSize(width: 430, height: 430 * base.size.height / base.size.width)
            let data = try #require(base.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let cgImage = try #require(bitmap.cgImage)
            let source = CIImage(cgImage: cgImage)
            let renderer = CIContext(options: [.cacheIntermediates: false])
            var started = false
            let overlay = NSHostingView(rootView: PaydayCelebrationView(language: language, theme: .cyan,
                didStart: { started = true }, didFinish: {}).frame(width: size.width, height: size.height))
            overlay.sizingOptions = []
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            overlay.frame = container.bounds
            container.addSubview(overlay)
            let window = NSWindow(contentRect: container.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.alphaValue = 0; window.ignoresMouseEvents = true
            window.appearance = NSAppearance(named: .darkAqua); window.contentView = container; window.orderFront(nil)
            defer { window.orderOut(nil); window.close() }
            for _ in 0 ..< 400 {
                if started { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(started, "发薪日文档动画未启动")
            func findWeb(_ view: NSView) -> WKWebView? {
                if let web = view as? WKWebView { return web }
                return view.subviews.lazy.compactMap(findWeb).first
            }
            let web = try #require(findWeb(overlay))
            _ = try await web.evaluateJavaScript("window.dayperkTimeline.pause(0); window.dayperkTimeline.eventCallback('onComplete', null); 0")
            let frames = directory.appendingPathComponent("payday-frames")
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            let fps = 15, count = Int(PaydayCelebrationState.duration) * fps
            for index in 0 ..< count {
                let time = Double(index) / Double(fps)
                _ = try await web.evaluateJavaScript("window.dayperkTimeline.pause(\(time)); 0")
                try await Task.sleep(for: .milliseconds(18))
                let effect = try await web.takeSnapshot(configuration: nil)
                try writeFrame(background: source, renderer: renderer, effect: effect, size: size, pixels: bitmap.pixelsWide, blur: blur(at: time),
                    to: frames.appendingPathComponent(String(format: "%03d.png", index)))
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: frames.path).filter { $0.hasSuffix(".png") }
            #expect(names.count == count)
            let first = try Data(contentsOf: frames.appendingPathComponent("000.png"))
            let peak = try Data(contentsOf: frames.appendingPathComponent("045.png"))
            #expect(first != peak)
            print("发薪日演示已导出：\(language)，\(count) 帧，\(fps) fps，目录：\(frames.path)")
        }
    }

    @MainActor private func writeFrame(background: CIImage, renderer: CIContext, effect: NSImage, size: NSSize, pixels: Int, blur: Double, to url: URL) throws {
        let scale = Double(pixels) / size.width
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        // SwiftUI 离屏缓存不包含 GPU 虚化，用系统滤镜保留原生面板的渐变虚化效果。
        let blurred = background.clampedToExtent().applyingGaussianBlur(sigma: blur * scale).cropped(to: background.extent)
        let image = try #require(renderer.createCGImage(blurred, from: background.extent))
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))
        let opacity = blur / 4
        let shade = try #require(NSGradient(colorsAndLocations: (NSColor.black.withAlphaComponent(0.02 * opacity), 0),
            (NSColor.black.withAlphaComponent(0.12 * opacity), 0.5), (NSColor.black.withAlphaComponent(0.04 * opacity), 1)))
        shade.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        effect.draw(in: NSRect(origin: .zero, size: size))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
    private func blur(at time: Double) -> Double {
        if time < 0.65 { return 0 }
        if time < 1.6 { return 4 * ease((time - 0.65) / 0.95) }
        if time < 8.05 { return 4 }
        return 4 * (1 - ease((time - 8.05) / 0.85))
    }

    // 与原生面板相同的 easeInOut 曲线，逐帧导出时不依赖墙上时钟。
    private func ease(_ progress: Double) -> Double {
        let target = min(1, max(0, progress))
        var lower = 0.0, upper = 1.0
        for _ in 0 ..< 16 {
            let t = (lower + upper) / 2, u = 1 - t
            let x = 3 * 0.42 * u * u * t + 3 * 0.58 * u * t * t + t * t * t
            if x < target { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }

}
