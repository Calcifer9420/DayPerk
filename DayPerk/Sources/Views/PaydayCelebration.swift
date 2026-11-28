import SwiftUI
import WebKit

struct PaydayCelebrationState: Equatable, Identifiable {
    static let duration = 10.0
    let id = UUID()
    var started: Date?
}

extension PaydayRule {
    func includes(_ date: Date, plan: WorkPlan, calendar: Calendar) -> Bool {
        // 下月发薪日可能提前到本月，不能只检查当前月份。
        for offset in 0 ... 1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: date),
                  let payday = self.date(year: calendar.component(.year, from: month),
                                        month: calendar.component(.month, from: month), plan: plan, calendar: calendar) else { continue }
            if calendar.isDate(date, inSameDayAs: payday) { return true }
        }
        return false
    }
}

/// 真实界面渐变虚化，庆祝图形单独叠在上方，不替换或隐藏原有控件。
struct PaydayBackdrop: ViewModifier {
    let started: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blur = 0.0

    func body(content: Content) -> some View {
        content.blur(radius: blur)
            .overlay {
                LinearGradient(colors: [.black.opacity(0.02), .black.opacity(0.12), .black.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom).opacity(blur / 4).allowsHitTesting(false)
            }
            .task(id: started) {
                blur = 0
                guard started != nil, !reduceMotion else { return }
                do {
                    try await Task.sleep(for: .milliseconds(650))
                    withAnimation(.easeInOut(duration: 0.95)) { blur = 4 }
                    try await Task.sleep(for: .milliseconds(7400))
                    withAnimation(.easeInOut(duration: 0.85)) { blur = 0 }
                } catch { blur = 0 }
            }
    }
}

/// 用系统 WebKit 离线播放已确认的逐字矢量动画，不传入薪资或工作记录。
struct PaydayCelebrationView: NSViewRepresentable {
    let language: String
    let theme: BrewTheme
    var didStart: () -> Void
    var didFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var resourceURL: URL? { Bundle.main.url(forResource: "PaydayCelebration", withExtension: "html") }

    func makeCoordinator() -> Coordinator { Coordinator(didStart: didStart, didFinish: didFinish) }

    func makeNSView(context: Context) -> PassiveWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let color = theme.nsColor.usingColorSpace(.sRGB) ?? theme.nsColor
        let options: [String: Any] = ["language": language,
            "accent": String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                             Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded())),
            "reduceMotion": reduceMotion]
        let data = try! JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        let source = "window.dayperkOptions=" + String(decoding: data, as: UTF8.self) + ";"
        configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "payday")
        let view = PassiveWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .clear
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        if let url = Self.resourceURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { DispatchQueue.main.async(execute: didFinish) }
        return view
    }

    func updateNSView(_: PassiveWebView, context: Context) {
        context.coordinator.didStart = didStart
        context.coordinator.didFinish = didFinish
    }

    static func dismantleNSView(_ view: PassiveWebView, coordinator _: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "payday")
        view.navigationDelegate = nil
    }

    final class PassiveWebView: WKWebView {
        override func hitTest(_: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var didStart: () -> Void
        var didFinish: () -> Void
        init(didStart: @escaping () -> Void, didFinish: @escaping () -> Void) {
            self.didStart = didStart; self.didFinish = didFinish
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.webView === webView,
                  let event = message.body as? String else { return }
            if event == "started" { didStart() }
            if event == "finished" || event == "failed" { didFinish() }
        }

        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let root = PaydayCelebrationView.resourceURL?.deletingLastPathComponent() else {
                decisionHandler(.cancel); return
            }
            decisionHandler(url.isFileURL && url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") ? .allow : .cancel)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) { didFinish() }
        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { didFinish() }
        func webViewWebContentProcessDidTerminate(_: WKWebView) { didFinish() }
    }
}
