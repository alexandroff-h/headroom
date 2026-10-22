import XCTest
@testable import HeadroomCore

/// All time and exit evidence is synthetic. These tests never launch, signal,
/// quit, or force quit a user application.
final class ActionLifecycleTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000)

    func testOverlappingActionsCannotReplaceAnyActivePhase() {
        var action = started()
        XCTAssertFalse(action.start(at: date(1)))
        XCTAssertEqual(action.deadline, date(12))
        baseline(&action)
        XCTAssertTrue(action.markRequested(at: date(6)))
        XCTAssertFalse(action.start(at: date(7)))
        XCTAssertEqual(action.status, .waitingForExit)
        XCTAssertEqual(action.deadline, date(26))
        action.advance(at: date(8), targetHasExited: true)
        XCTAssertFalse(action.start(at: date(9)))
        XCTAssertEqual(action.status, .settling)
        XCTAssertEqual(action.exitObservedAt, date(8))
    }

    func testBaselineNeedsThreeFreshReadingsBeforeOneRequest() {
        var action = started()
        feed(&action, at: 2)
        feed(&action, at: 4)
        XCTAssertFalse(action.canRequest(at: date(4)))
        XCTAssertFalse(action.markRequested(at: date(4)))
        feed(&action, at: 6)
        XCTAssertTrue(action.markRequested(at: date(6)))
        XCTAssertFalse(action.markRequested(at: date(7)), "Only one OS request per action")
    }

    func testHiddenOrOldPreActionSamplesCannotSupplyBaseline() {
        var action = started()
        feed(&action, at: -4)
        feed(&action, at: -2)
        feed(&action, at: 0)
        feed(&action, at: 2, intervalStart: -8) // first sample after a hidden-window pause
        XCTAssertFalse(action.canRequest(at: date(2)))
        action.advance(at: date(12), targetHasExited: false)
        XCTAssertEqual(action.status, .baselineUnavailable)
        assertUnknown(action)
    }

    func testBaselineCannotBecomeStaleWhileRequestIsDelayed() {
        var action = started()
        baseline(&action)
        XCTAssertTrue(action.canRequest(at: date(6)))
        XCTAssertFalse(action.markRequested(at: date(9)))
        XCTAssertEqual(action.status, .preparing)
    }

    func testDuplicateOutOfOrderAndFutureReadingsAreNotThreeSamples() {
        var action = started()
        feed(&action, at: 2)
        feed(&action, at: 2)
        feed(&action, at: 1, intervalStart: 0)
        action.receive(reading(at: 6), at: date(3))
        feed(&action, at: 4)
        XCTAssertFalse(action.canRequest(at: date(4)))
        feed(&action, at: 6)
        XCTAssertTrue(action.canRequest(at: date(6)))
    }

    func testRequestRejectionFinishesUnknownAndCanBeRetried() {
        var action = requested()
        action.requestRejected()
        XCTAssertEqual(action.status, .requestRejected)
        assertUnknown(action)
        action.advance(at: date(8), targetHasExited: true)
        XCTAssertNil(action.exitObservedAt)
        XCTAssertTrue(action.start(at: date(9)))
        XCTAssertNil(action.outcome)
        XCTAssertFalse(action.canRequest(at: date(9)), "A retry cannot reuse the last baseline")
    }

    func testAcceptedRequestOrFallingMemoryCannotProveExit() {
        var action = requested()
        // The app could have refused its save dialog while another process
        // independently released memory. Neither time nor gains prove exit.
        for time in stride(from: 8.0, through: 24.0, by: 2) {
            feed(&action, at: time, memory: 100_000_000, cpu: 1)
            action.advance(at: date(time), targetHasExited: false)
        }
        XCTAssertEqual(action.status, .waitingForExit)
        XCTAssertNil(action.outcome)
        action.advance(at: date(26), targetHasExited: false)
        XCTAssertEqual(action.status, .exitTimedOut)
        assertUnknown(action)
        action.advance(at: date(27), targetHasExited: true)
        XCTAssertNil(action.exitObservedAt, "A late exit cannot turn a timed-out action into a win")
    }

    func testExitFirstObservedAfterTimeoutCannotStartMeasurement() {
        var action = requested()
        action.advance(at: date(27), targetHasExited: true)
        XCTAssertEqual(action.status, .exitTimedOut)
        XCTAssertNil(action.exitObservedAt)
        assertUnknown(action)
    }

    func testAfterMedianUsesThreeNewIntervalsAfterConfirmedExitAndSettle() {
        var action = requested()
        feed(&action, at: 8, memory: 1, cpu: 1) // waiting, not exited
        action.advance(at: date(10), targetHasExited: true)
        XCTAssertEqual(action.deadline, date(34)) // exit + settle + sample bound
        feed(&action, at: 12, memory: 1, cpu: 1) // exited, not settled
        feed(&action, at: 22, memory: 1, cpu: 1) // interval still straddles settle boundary
        XCTAssertNil(action.outcome)
        feed(&action, at: 24, memory: 600_000_000, cpu: 9)
        feed(&action, at: 26, memory: 1, cpu: 0) // one spike cannot set the median
        XCTAssertNil(action.outcome)
        feed(&action, at: 28, memory: 700_000_000, cpu: 11)
        XCTAssertEqual(action.status, .measured)
        XCTAssertEqual(action.outcome?.verdict, .freed)
        XCTAssertEqual(action.outcome?.memoryDeltaBytes, 1_400_000_000)
        XCTAssertEqual(action.outcome?.cpuDelta, 11)
    }

    func testMissingReadingsCannotLeakOldValuesIntoEitherMedian() {
        var action = started()
        feed(&action, at: 2, memory: nil, cpu: 20)
        feed(&action, at: 4, memory: 2_000_000_000, cpu: 20)
        feed(&action, at: 6, memory: 2_000_000_000, cpu: 20)
        XCTAssertTrue(action.markRequested(at: date(6)))
        action.advance(at: date(8), targetHasExited: true)
        feed(&action, at: 22, memory: 1, cpu: 10)
        feed(&action, at: 24, memory: 1, cpu: 10)
        feed(&action, at: 26, memory: 1, cpu: 10)
        XCTAssertNil(action.outcome?.memoryDeltaBytes)
        XCTAssertEqual(action.outcome?.cpuDelta, 10)
        XCTAssertEqual(action.outcome?.verdict, .freed)

        var missingAfter = requested()
        missingAfter.advance(at: date(8), targetHasExited: true)
        feed(&missingAfter, at: 22, memory: 1, cpu: nil)
        feed(&missingAfter, at: 24, memory: nil, cpu: 1)
        feed(&missingAfter, at: 26, memory: 1, cpu: 1)
        XCTAssertEqual(missingAfter.status, .readingsUnavailable)
        assertUnknown(missingAfter)
        XCTAssertEqual(missingAfter.exitObservedAt, date(8))
    }

    func testTwoAfterSamplesThenSilenceFinishUnknownOnDeadline() {
        var action = requested()
        action.advance(at: date(8), targetHasExited: true)
        feed(&action, at: 22, memory: 1)
        feed(&action, at: 24, memory: 1)
        XCTAssertNil(action.outcome)
        action.advance(at: date(32), targetHasExited: false)
        XCTAssertEqual(action.status, .readingsUnavailable)
        assertUnknown(action)
    }

    func testStaleAfterSamplesAreDiscardedInsteadOfCompletingMedian() {
        var action = requested()
        action.advance(at: date(8), targetHasExited: true)
        feed(&action, at: 22, memory: 1)
        feed(&action, at: 24, memory: 1)
        feed(&action, at: 30, intervalStart: 28, memory: 1)
        XCTAssertNil(action.outcome, "The oldest interval is now ten seconds old")
        action.advance(at: date(32), targetHasExited: false)
        assertUnknown(action)
    }

    func testUnavailableBaselineDoesNotTurnUnknownIntoZero() {
        var action = started()
        for time in [2.0, 4, 6] { feed(&action, at: time, memory: nil, cpu: nil) }
        XCTAssertFalse(action.markRequested(at: date(6)))
        action.advance(at: date(12), targetHasExited: false)
        assertUnknown(action)
    }

    func testExistingNoiseFloorsAreUsedForMeasuredResults() {
        for (memoryAfter, expected): (UInt64, ImpactVerdict) in [
            (2_000_000_000 - UInt64(Impact.memoryNoiseFloor) + 1, .noChange),
            (2_000_000_000 - UInt64(Impact.memoryNoiseFloor), .freed),
            (2_000_000_000 + UInt64(Impact.memoryNoiseFloor), .offset)
        ] {
            var action = requested()
            action.advance(at: date(8), targetHasExited: true)
            for time in [22.0, 24, 26] { feed(&action, at: time, memory: memoryAfter, cpu: 20) }
            XCTAssertEqual(action.outcome?.verdict, expected)
        }
    }

    func testUnrepresentableMemoryDeltaAndInvalidCPUStayUnknown() {
        var action = started()
        for time in [2.0, 4, 6] { feed(&action, at: time, memory: UInt64.max, cpu: .nan) }
        XCTAssertTrue(action.markRequested(at: date(6)))
        action.advance(at: date(8), targetHasExited: true)
        for time in [22.0, 24, 26] { feed(&action, at: time, memory: 0, cpu: .infinity) }
        assertUnknown(action)
    }

    func testTargetDisappearingBeforeRequestAndCancellationNeverClaimWin() {
        var unavailable = started()
        unavailable.targetUnavailable()
        XCTAssertEqual(unavailable.status, .targetUnavailable)
        assertUnknown(unavailable)

        var action = requested()
        action.cancel()
        XCTAssertEqual(action.status, .interrupted)
        XCTAssertNil(action.exitObservedAt)
        assertUnknown(action)

        var exited = requested()
        exited.advance(at: date(8), targetHasExited: true)
        exited.cancel()
        XCTAssertEqual(exited.exitObservedAt, date(8))
        assertUnknown(exited)
    }

    private func started() -> ActionLifecycle {
        var action = ActionLifecycle()
        XCTAssertTrue(action.start(at: origin))
        return action
    }

    private func requested() -> ActionLifecycle {
        var action = started()
        baseline(&action)
        XCTAssertTrue(action.markRequested(at: date(6)))
        return action
    }

    private func baseline(_ action: inout ActionLifecycle) {
        feed(&action, at: 2, memory: 2_000_000_000, cpu: 20)
        feed(&action, at: 4, memory: 9_000_000_000, cpu: 90)
        feed(&action, at: 6, memory: 2_000_000_000, cpu: 20)
    }

    private func date(_ seconds: TimeInterval) -> Date { origin.addingTimeInterval(seconds) }

    private func reading(at seconds: TimeInterval, intervalStart: TimeInterval? = nil,
                         memory: UInt64? = 2_000_000_000, cpu: Double? = 20) -> ActionLifecycle.Reading {
        ActionLifecycle.Reading(timestamp: date(seconds), intervalStartedAt: date(intervalStart ?? seconds - 2),
                                memoryBytes: memory, cpuPercent: cpu)
    }

    private func feed(_ action: inout ActionLifecycle, at seconds: TimeInterval,
                      intervalStart: TimeInterval? = nil, memory: UInt64? = 2_000_000_000, cpu: Double? = 20) {
        action.receive(reading(at: seconds, intervalStart: intervalStart, memory: memory, cpu: cpu), at: date(seconds))
    }

    private func assertUnknown(_ action: ActionLifecycle, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(action.isMeasuring, file: file, line: line)
        XCTAssertEqual(action.outcome?.verdict, .unknown, file: file, line: line)
        XCTAssertNil(action.outcome?.memoryDeltaBytes, file: file, line: line)
        XCTAssertNil(action.outcome?.cpuDelta, file: file, line: line)
    }
}
