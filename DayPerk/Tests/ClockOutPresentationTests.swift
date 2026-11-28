import Foundation
import Testing
@testable import DayPerk

struct ClockOutPresentationTests {
    @Test func showcaseHidesMenuBarPayEvenDuringClockOutCelebrations() {
        for working in [true, false] {
            for retain in [true, false] {
                #expect(StatusBarPresentation.amount(495, privateMode: false, showcase: true,
                    isWorking: working, hideWhenPaused: false, retainForCelebration: retain).isEmpty)
            }
        }
    }
    @Test func menuAmountStaysUntilTheSharedAnimationEnd() {
        let start = Date(timeIntervalSince1970: 100)
        let celebration = ClockOutCelebrationState(started: start, menuAmountWasVisible: true)
        for elapsed in [0.0, 2, ClockOutConfetti.duration - 0.001, ClockOutConfetti.duration, ClockOutConfetti.duration + 1] {
            let retained = celebration.retainsMenuAmount(at: start.addingTimeInterval(elapsed))
            let text = StatusBarPresentation.amount(495, privateMode: false, isWorking: false,
                hideWhenPaused: true, retainForCelebration: retained)
            #expect(text == (elapsed < ClockOutConfetti.duration ? "495" : ""))
        }
    }

    @Test func privacyAndGlobalLockAlwaysOverrideAnimationRetention() {
        for hidden in [false, true] {
            for locked in [false, true] {
                let text = StatusBarPresentation.amount(495, privateMode: hidden || locked, isWorking: false,
                    hideWhenPaused: true, retainForCelebration: true)
                #expect(text == (!hidden && !locked ? "495" : ""))
            }
        }
    }

    @Test func anAlreadyHiddenAmountDoesNotFlashAndResumeDoesNotHideIt() {
        let start = Date(timeIntervalSince1970: 100)
        let celebration = ClockOutCelebrationState(started: start, menuAmountWasVisible: false)
        #expect(!celebration.retainsMenuAmount(at: start.addingTimeInterval(1)))
        #expect(StatusBarPresentation.amount(495, privateMode: false, isWorking: false,
            retainForCelebration: celebration.retainsMenuAmount(at: start.addingTimeInterval(1))).isEmpty)
        #expect(StatusBarPresentation.amount(495, privateMode: false, isWorking: true, retainForCelebration: false) == "495")
        #expect(StatusBarPresentation.amount(495, privateMode: false, isWorking: false, hideWhenPaused: false) == "495")
    }

    @MainActor @Test(.enabled(if: Bundle.main.bundleIdentifier?.hasPrefix("app.dayperk.documentation.") == true))
    func actualClockOutRetentionExpiresAndPrivacyCanCancelIt() async throws {
        // 仅在隔离演示域运行计时集成测试，不生成文档或读取个人安装。
        try #require(LocalPreviewMode.permitsSampleData(bundleIdentifier: Bundle.main.bundleIdentifier))
        var seed = try LocalPreviewMode.loadSeed(); seed.language = "zh-Hans"; seed.monthlySalary = 11_454
        try LocalPreviewMode.prepare(seed)
        UserDataStore.shared.set(true, forKey: "hideAmountWhenPaused")
        let model = DayPerkModel()
        defer { model.endClockOutCelebration(); model.tracking.discardForRestore() }
        try LocalPreviewMode.apply(seed, to: model)
        model.tracking.setWorking(true)
        try model.tracking.correctToday(seconds: 2 * 3600)
        #expect(model.access.hideWhenPaused && !model.privacy.isPrivacyModeEnabled)
        model.finishToday()
        let celebration = try #require(model.clockOutCelebration)
        #expect(model.isTodaySettled && !model.tracking.state.isWorking)
        #expect(celebration.menuAmountWasVisible && celebration.retainsMenuAmount(at: Date()))
        try await Task.sleep(for: .seconds(1))
        #expect(model.clockOutCelebration?.started == celebration.started)
        let remaining = max(0, celebration.endsAt.timeIntervalSinceNow) + 0.15
        try await Task.sleep(for: .seconds(remaining))
        #expect(model.clockOutCelebration == nil)
        let retainAfterAnimation = model.clockOutCelebration?.retainsMenuAmount(at: Date()) == true
        #expect(StatusBarPresentation.amount(model.today.earned, privateMode: false, isWorking: false,
            retainForCelebration: retainAfterAnimation).isEmpty)

        model.tracking.setWorking(true)
        try model.tracking.correctToday(seconds: 2 * 3600)
        model.finishToday()
        #expect(model.clockOutCelebration != nil)
        model.access.setSensitiveInformationHidden(true, privacy: model.privacy)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.privacy.isPrivacyModeEnabled && model.clockOutCelebration == nil)
    }
}
