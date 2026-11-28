import Testing
@testable import DayPerk

struct ActionFeedbackTests {
    @MainActor @Test func repeatActionsRestartTheToastAndAnOldTimerCannotDismissTheNewOne() throws {
        let center = ActionToastCenter()
        center.show("action.saved")
        let first = try #require(center.current)
        center.show("action.saved")
        let second = try #require(center.current)
        #expect(first.id != second.id)
        center.dismiss(id: first.id)
        #expect(center.current?.id == second.id)
        center.dismiss(id: second.id)
        #expect(center.current == nil)
    }

    @MainActor @Test func errorsAndEmptyFeedbackAreHandledWithoutReplacingTheCurrentMessage() throws {
        let center = ActionToastCenter()
        center.show("action.saved", isError: true)
        let message = try #require(center.current)
        center.show("  ")
        #expect(center.current?.id == message.id && center.current?.isError == true)
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test func workStatusUsesActualUnpaidTimeAndDoesNotMarkPausedTimeAsOvertime() {
        for registered in [false, true] {
            for exceeded in [false, true] {
                #expect(DashboardWorkStatus(isWorking: false, isSettled: false, isRegisteredOvertime: registered, exceededReference: exceeded) == .paused)
                #expect(DashboardWorkStatus(isWorking: false, isSettled: true, isRegisteredOvertime: registered, exceededReference: exceeded) == .clockedOut)
                #expect(DashboardWorkStatus(isWorking: true, isSettled: false, isRegisteredOvertime: registered, exceededReference: exceeded)
                    == (exceeded ? .unpaidOvertime : registered ? .overtime : .working))
            }
        }
    }
}
