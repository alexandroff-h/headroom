import XCTest
@testable import HeadroomCore

/// Headroom's one claim about improvement is the measured delta after an
/// action. These tests hold it to being a measurement: a difference inside the
/// noise floor must never be reported as a win, and a negative one must never
/// be reported at all.
final class ImpactTests: XCTestCase {
    func testAClearGainIsAWin() {
        XCTAssertEqual(Impact.classify(memoryDelta: 1_200_000_000, cpuDelta: 0.4), .freed)
    }

    func testADifferenceInsideTheNoiseFloorIsNotAWin() {
        XCTAssertEqual(Impact.classify(memoryDelta: 20_000_000, cpuDelta: 0.5), .noChange)
        XCTAssertEqual(Impact.classify(memoryDelta: Impact.memoryNoiseFloor - 1, cpuDelta: nil), .noChange)
    }

    func testMemoryGoingUpIsReportedAsOffsetRatherThanAsALoss() {
        XCTAssertEqual(Impact.classify(memoryDelta: -900_000_000, cpuDelta: nil), .offset)
    }

    /// An app can give back processor time without giving back much memory.
    func testProcessorAloneCanCarryAWin() {
        XCTAssertEqual(Impact.classify(memoryDelta: 10_000_000, cpuDelta: 24), .freed)
    }

    func testNoReadingMeansUnknownRatherThanZero() {
        XCTAssertEqual(Impact.classify(memoryDelta: nil, cpuDelta: nil), .unknown)
    }

    func testOnlyWinsAreBanked() {
        XCTAssertEqual(record(verdict: .freed, memory: 1_000_000_000).memoryWon, 1_000_000_000)
        XCTAssertEqual(record(verdict: .noChange, memory: 1_000_000_000).memoryWon, 0)
        XCTAssertEqual(record(verdict: .offset, memory: -1_000_000_000).memoryWon, 0)
        XCTAssertEqual(record(verdict: .unknown, memory: nil).memoryWon, 0)
    }

    func testRecapSumsOnlyMeasuredWins() {
        let recap = ActionLedger.summarise(
            [
                record(verdict: .freed, memory: 1_000_000_000),
                record(verdict: .freed, memory: 500_000_000),
                record(verdict: .noChange, memory: 30_000_000),
                record(verdict: .offset, memory: -800_000_000),
            ],
            start: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(recap.memoryFreedBytes, 1_500_000_000)
        // Every action still counts, because the reader took it.
        XCTAssertEqual(recap.actionCount, 4)
    }

    /// Processor use is a rate. Adding Tuesday's 6% to Friday's 11% produces a
    /// number that is not true about anything, so the recap reports the best
    /// single action instead.
    func testProcessorGainIsNeverSummed() {
        let recap = ActionLedger.summarise(
            [
                record(verdict: .freed, memory: 1_000_000_000, cpu: 6),
                record(verdict: .freed, memory: 1_000_000_000, cpu: 11),
                record(verdict: .freed, memory: 1_000_000_000, cpu: 32),
            ],
            start: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(recap.bestCPUGain, 32)
    }

    func testRepeatsNameWhatKeepsComingBack() {
        let recap = ActionLedger.summarise(
            [
                record(name: "Slack", verdict: .freed, memory: 1_000_000_000),
                record(name: "Slack", verdict: .freed, memory: 900_000_000),
                record(name: "Slack", verdict: .noChange, memory: 1_000_000),
                record(name: "Docker", verdict: .freed, memory: 2_000_000_000),
            ],
            start: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(recap.repeats.count, 1)
        XCTAssertEqual(recap.repeats[0].name, "Slack")
        XCTAssertEqual(recap.repeats[0].count, 3)
        XCTAssertEqual(recap.repeats[0].memoryBytes, 1_900_000_000)
    }

    func testTheRecordSurvivesALaunch() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("headroom-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writing = ActionLedger(directory: directory)
        let entry = record(name: "Docker", verdict: .measuring, memory: nil)
        await writing.append(entry)
        _ = await writing.update(id: entry.id, verdict: .freed, memoryDeltaBytes: 3_000_000_000, cpuDelta: 8)

        let reading = ActionLedger(directory: directory)
        let all = await reading.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].verdict, .freed)
        XCTAssertEqual(all[0].memoryDeltaBytes, 3_000_000_000)

        await reading.erase()
        let after = await ActionLedger(directory: directory).all()
        XCTAssertTrue(after.isEmpty, "Erase has to leave nothing behind on disk")
    }

    private func record(name: String = "Slack", verdict: ImpactVerdict, memory: Int64?, cpu: Double? = nil) -> ActionRecord {
        ActionRecord(
            appName: name,
            appID: "bundle:/Applications/\(name).app",
            kind: .quit,
            footprintBytes: 2_000_000_000,
            footprintCPU: 2,
            verdict: verdict,
            memoryDeltaBytes: memory,
            cpuDelta: cpu
        )
    }
}
