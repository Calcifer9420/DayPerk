import AppKit

enum PreferencesWindowLayout {
    static let defaultSize = NSSize(width: 980, height: 820)
    static let minimumSize = NSSize(width: 900, height: 740)

    /// 用普通容器隔开 SwiftUI 的内容尺寸，替换页面时保留实际窗口边框。
    static func install(_ view: NSView, in window: NSWindow) {
        let frame = window.frame
        window.appearance = NSAppearance(named: .darkAqua)
        let container = NSView(frame: window.contentView?.bounds ?? NSRect(origin: .zero, size: defaultSize))
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        window.contentViewController = nil
        window.contentView = container
        window.setFrame(frame, display: false)
    }
}
