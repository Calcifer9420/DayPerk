import AppKit
@testable import DayPerk
import Testing

struct HelpPopoverTests {
    @MainActor @Test func explanationsUseEitherSideWithoutShrinkingInteractiveContent() throws {
        let screen = try #require(NSScreen.main)
        let frame = NSRect(x: screen.visibleFrame.maxX - 430, y: screen.visibleFrame.midY - 200, width: 430, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = host
        let button = HoverHelpButton()
        button.frame = NSRect(x: 290, y: 180, width: 18, height: 18)
        button.explanation = WorkTimeZoneOptions.explanation
        host.addSubview(button)
        #expect(button.makeContent().frame.width == 342)
        button.preferredEdge = .maxX
        let narrow = button.makeContent()
        #expect(narrow.frame.width >= 280)
        button.frame.origin.x = 30
        let wide = button.makeContent()
        #expect(wide.frame.width == narrow.frame.width)
        #expect(narrow.frame.height >= wide.frame.height)
        #expect(narrow.frame.height < 400)
        button.options = [HelpOption(title: "计入年终奖", isOn: true) { _ in }]
        #expect(button.makeContent().frame.width == 342)
        button.formula = [HelpFormulaRow(amount: "8 小时", label: "每日参考工时")]
        #expect(button.makeContent().frame.width == 378)
        window.contentView = nil
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func popoversAvoidAllAncestorsAtEveryScreenEdge() throws {
        let screen = try #require(NSScreen.main).visibleFrame
        for width in [CGFloat(430), CGFloat(980)] {
            let height: CGFloat = min(600, screen.height - 40)
            for x in [screen.minX + 8, screen.midX - width / 2, screen.maxX - width - 8] {
                for y in [screen.minY + 8, screen.midY - height / 2, screen.maxY - height - 8] {
                    let window = NSWindow(contentRect: NSRect(x: x, y: y, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.identifier = NSUserInterfaceItemIdentifier(width == 430 ? "DayPerk-dashboard" : "DayPerk-preferences")
                    let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height)); window.contentView = host
                    window.alphaValue = 0; window.ignoresMouseEvents = true; window.orderFront(nil)
                    defer { HoverHelpButton.closeActive(); window.orderOut(nil); window.close() }
                    for point in [NSPoint(x: 20, y: height - 40), NSPoint(x: width / 2, y: height / 2), NSPoint(x: width - 40, y: 20)] {
                        let button = HoverHelpButton(); button.frame.origin = point
                        button.explanation = WorkTimeZoneOptions.explanation; host.addSubview(button)
                        if width == 430 {
                            button.hours = WorkHoursExplanation(title: "每日参考计费 8 小时", detail: "每日参考工时", rows: [HelpFormulaRow(amount: "8 小时", label: "每日参考工时")])
                        }
                        try autoreleasepool { try Self.checkPosition(of: button, context: "\(width), \(point)") }
                        button.removeFromSuperview()
                    }
                }
            }
        }
    }

    @MainActor static func questions(in view: NSView) -> [HoverHelpButton] {
        (view as? HoverHelpButton).map { [$0] } ?? view.subviews.flatMap { questions(in: $0) }
    }

    @MainActor static func checkPosition(of button: HoverHelpButton, context: String, ancestors: [NSRect] = []) throws {
        let source = try #require(button.window)
        let question = source.convertToScreen(button.convert(button.bounds, to: nil))
        let existing = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let action = try #require(button.action)
        NSApp.sendAction(action, to: button.target, from: button)
        let popover = try #require(NSApp.windows.first { $0.identifier?.rawValue == "DayPerk-help" && $0.isVisible && !existing.contains(ObjectIdentifier($0)) }, Comment(rawValue: context + ": 宿主 \(source.identifier?.rawValue ?? "无标识")，问号 \(question)，可见范围 \(button.visibleRect)，边界 \(button.bounds)，隐藏 \(button.isHiddenOrHasHiddenAncestor)，现有说明 \(NSApp.windows.filter { $0.identifier?.rawValue == "DayPerk-help" && $0.isVisible }.map { (ObjectIdentifier($0), $0.frame, existing.contains(ObjectIdentifier($0))) })"))
        popover.alphaValue = 0
        let frame = popover.frame
        let screen = try #require(source.screen).visibleFrame.insetBy(dx: -12, dy: -12)
        let local = ancestors.isEmpty && source.identifier?.rawValue == "DayPerk-preferences"
        let anchor = local ? question : source.frame
        let dx = max(0, anchor.minX - frame.maxX, frame.minX - anchor.maxX)
        let dy = max(0, anchor.minY - frame.maxY, frame.minY - anchor.maxY)
        #expect(hypot(dx, dy) <= 32, Comment(rawValue: context + ": \(anchor) -> \(frame)"))
        let obstacles = local ? ancestors : ancestors + [source.frame]
        for obstacle in obstacles {
            #expect(!frame.intersects(obstacle), Comment(rawValue: context + ": \(frame) overlaps \(obstacle)"))
        }
        if !local, ancestors.isEmpty {
            let leading = question.midX <= source.frame.midX
            let available = leading ? source.frame.minX - screen.minX : screen.maxX - source.frame.maxX
            if available >= frame.width + 20 {
                #expect(leading ? frame.maxX <= source.frame.minX : frame.minX >= source.frame.maxX, Comment(rawValue: context + ": 优先贴近问号所在的一侧"))
            }
        }
        #expect(screen.contains(frame), Comment(rawValue: context + ": \(frame) outside \(screen)"))
        if let content = popover.contentView {
            for child in questions(in: content) { try checkPosition(of: child, context: context + " / nested", ancestors: obstacles) }
        }
        HoverHelpButton.closeActive()
    }

    @Test func timeZoneHelpHasChineseTranslation() throws {
        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let text = bundle.localizedString(forKey: WorkTimeZoneOptions.explanationKey, value: nil, table: "Localizable")
        #expect(text.contains("夏令时") && text.contains("UTC"))
        #expect(!text.contains("Regional presets"))
        #expect(RuleHelpText.bulleted(text).components(separatedBy: "• ").count == 4)
    }
}
