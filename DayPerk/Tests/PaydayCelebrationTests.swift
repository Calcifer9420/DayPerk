import AppKit
import SwiftUI
import Testing
import WebKit
@testable import DayPerk

struct PaydayCelebrationTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func fixedMonthEndAndLeapYearDatesMatchOnlyTheActualPayday() {
        let c = calendar(), plan = WorkPlan()
        let fixed = PaydayRule(usesLastDay: false, day: 31)
        for (year, day) in [(2026, 28), (2028, 29)] {
            #expect(fixed.includes(date(year, 2, day, calendar: c), plan: plan, calendar: c))
            #expect(!fixed.includes(date(year, 2, day - 1, calendar: c), plan: plan, calendar: c))
        }
        #expect(PaydayRule().includes(date(2026, 11, 30, calendar: c), plan: plan, calendar: c))
        #expect(!PaydayRule().includes(date(2026, 11, 29, calendar: c), plan: plan, calendar: c))
    }

    @Test func anAdvancedPaydayCanBelongToTheFollowingMonth() {
        let c = calendar(), plan = WorkPlan(weekdays: Set(2 ... 6))
        let rule = PaydayRule(usesLastDay: false, day: 1, advanceOnRestDay: true)
        #expect(rule.includes(date(2026, 1, 30, calendar: c), plan: plan, calendar: c))
        #expect(!rule.includes(date(2026, 2, 1, calendar: c), plan: plan, calendar: c))
        var makeup = plan
        makeup.dateOverrides["2026-01-31"] = true
        #expect(rule.includes(date(2026, 1, 31, calendar: c), plan: makeup, calendar: c))
        #expect(!rule.includes(date(2026, 1, 30, calendar: c), plan: makeup, calendar: c))
    }

    @Test func paydayUsesTheConfiguredWorkTimeZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-30T07:30:00Z"))
        let rule = PaydayRule(usesLastDay: false, day: 30)
        #expect(!rule.includes(instant, plan: WorkPlan(), calendar: calendar("America/Los_Angeles")))
        #expect(rule.includes(instant, plan: WorkPlan(), calendar: calendar("Asia/Tokyo")))
    }

    @Test func allOfflineResourcesAndTheirAttributionsAreBundled() throws {
        let url = try #require(PaydayCelebrationView.resourceURL)
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(!html.contains("dashboard.png"))
        #expect(!html.contains("class=\"dashboard-ui\""))
        #expect(html.contains("connect-src 'none'"))
        for name in ["PaydayGSAP.js", "PaydayConfetti.js", "PaydayGlyphs.js", "StarLoveSweety-AUTHORIZATION.txt",
                     "DynaPuff-LICENSE.txt", "MochiyPopOne-LICENSE.txt", "BagelFatOne-LICENSE.txt", "GSAP-NOTICE.txt"] {
            let file = url.deletingLastPathComponent().appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: file.path), "缺少随软件分发的资源：\(name)")
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.tests.") == true))
    func nativeWebKitLoadsEveryLanguageAndKeepsThePanelTransparent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DayPerkNativePaydayReview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("原生发薪日截图目录：" + directory.path)
        let titles = ["zh-Hans": "发工资啦！", "zh-Hant": "發薪水啦！", "en": "Payday!", "fr": "Jour de paie !",
                      "de": "Zahltag!", "ja": "給料日！", "ko": "월급날!"]
        for language in ["zh-Hans", "zh-Hant", "en", "fr", "de", "ja", "ko"] {
            var started = false
            let host = NSHostingView(rootView: PaydayCelebrationView(language: language, theme: .mint,
                didStart: { started = true }, didFinish: {}).frame(width: 430, height: 600))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.alphaValue = 0; window.ignoresMouseEvents = true
            window.contentView = host; window.orderFront(nil)
            defer { window.orderOut(nil); window.close() }
            for _ in 0 ..< 400 {
                if started { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(started, "原生 WebKit 未能启动：\(language)")
            func findWebView(_ view: NSView) -> WKWebView? {
                if let result = view as? WKWebView { return result }
                return view.subviews.lazy.compactMap(findWebView).first
            }
            let web = try #require(findWebView(host))
            let data = try await web.evaluateJavaScript("""
            window.dayperkTimeline.pause(2.5);
            ({title:document.querySelector('h1').getAttribute('aria-label'),
              duration:window.dayperkTimeline.duration(),
              accent:getComputedStyle(document.querySelector('#hat-band')).fill,
              glyphs:document.querySelectorAll('.glyph-body').length,
              language:document.querySelector('h1').lang})
            """)
            let values = try #require(data as? [String: Any])
            #expect(values["title"] as? String == titles[language])
            #expect(values["language"] as? String == language)
            #expect(values["duration"] as? Double == 10)
            #expect((values["glyphs"] as? Int ?? 0) > 0)
            #expect(values["accent"] as? String == "rgb(94, 227, 179)")
            #expect(web.hitTest(NSPoint(x: 200, y: 200)) == nil)
            let image = try await web.takeSnapshot(configuration: nil)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.02)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(language + ".png"))
        }
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.tests.") == true))
    func billingTransitionsStartAndCancelTheCelebrationWithoutChangingUserOptions() async throws {
        let model = DayPerkModel(authenticate: { _, completion in completion(true) })
        defer { model.endPaydayCelebration(); model.tracking.shutdown() }
        model.access.unlockAllData()
        model.access.setSensitiveInformationHidden(false, privacy: model.privacy)
        var configuration = model.configuration
        configuration.baseSalary = 114_514
        configuration.currency = .cny
        configuration.payday = PaydayRule(usesLastDay: false, day: model.workCalendar.component(.day, from: Date()))
        configuration.dateOverrides[WorkPlan.dayKey(Date(), calendar: model.workCalendar)] = true
        try model.saveConfiguration(configuration)
        let saved = model.configuration
        let host = NSHostingView(rootView: DayPerkDashboardView(model: model, openSettings: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: model.preferredPanelHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.alphaValue = 0; window.ignoresMouseEvents = true
        window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        model.tracking.setWorking(false)
        model.tracking.setWorking(true)
        let first = try #require(model.paydayCelebration)
        #expect(first.started == nil)
        for _ in 0 ..< 400 {
            if model.paydayCelebration?.started != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(model.paydayCelebration?.started != nil, "实际面板没有启动发薪日动画")
        model.tracking.updatePlan(model.tracking.plan)
        #expect(model.paydayCelebration?.id == first.id)
        model.tracking.setWorking(false)
        #expect(model.paydayCelebration == nil)
        model.tracking.setWorking(true)
        #expect(model.paydayCelebration?.id != first.id)
        model.access.lockAllData()
        #expect(model.paydayCelebration == nil)
        #expect(model.configuration.payday == saved.payday)
        #expect(model.configuration.rhythm == saved.rhythm)
        #expect(model.configuration.baseSalary == saved.baseSalary)
        #expect(model.configuration.timeZoneID == saved.timeZoneID)
    }
}
