import Foundation
import XCTest
@testable import HeadroomCore

final class DiagnosisEngineTests: XCTestCase {
    func testHighMemoryUsageWithoutPressureIsHealthy() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(memoryUsed: 31_000_000_000, pressure: .normal))
        XCTAssertEqual(diagnosis.severity, .healthy)
        XCTAssertEqual(diagnosis.cause, .none)
    }

    func testMemoryPressureWithModerateUsageNeedsAttention() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(memoryUsed: 10_000_000_000, pressure: .warning))
        XCTAssertEqual(diagnosis.severity, .attention)
        XCTAssertEqual(diagnosis.cause, .memory)
    }

    func testCriticalMemoryPressureIsCritical() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(pressure: .critical)).severity, .critical)
    }

    func testRetainedSwapDoesNotMeanCurrentMemoryPressure() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(swap: 12_000_000_000))
        XCTAssertEqual(diagnosis.severity, .healthy)
    }

    func testUnknownPressureCannotProduceHealthyDiagnosis() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(pressure: .unknown)).severity, .attention)
    }

    func testFirstCPUSampleShowsWarmingState() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(cpu: nil))
        XCTAssertEqual(diagnosis.severity, .attention)
        XCTAssertEqual(diagnosis.cause, .none)
        XCTAssertTrue(diagnosis.title.contains("Getting a feel"))
    }

    func testBusyCPUFlagsLikelyProcessorBottleneck() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(cpu: 91))
        XCTAssertEqual(diagnosis.cause, .cpu)
        XCTAssertEqual(diagnosis.severity, .attention)
    }

    func testBriefModerateCPUIsHealthy() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(cpu: 62)).severity, .healthy)
    }

    func testThermalPressureTakesPriorityOverCPU() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(cpu: 99, thermal: .serious))
        XCTAssertEqual(diagnosis.cause, .thermal)
    }

    func testCriticalHeatIsCritical() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(thermal: .critical)).severity, .critical)
    }

    func testLowAbsoluteStorageIsFlagged() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(diskFree: 4_000_000_000)).cause, .storage)
    }

    /// A merely full disk is not a performance problem, and saying it is would
    /// turn Headroom into the disk-cleaner category it is deliberately not in.
    func testAFullButWorkableDiskIsNotAPerformanceProblem() {
        let diagnosis = DiagnosisEngine.evaluate(snapshot: snapshot(diskFree: 40_000_000_000, diskTotal: 1_000_000_000_000))
        XCTAssertEqual(diagnosis.severity, .healthy)
    }

    /// Storage only matters once macOS cannot swap into it.
    func testStorageTooLowToSwapIntoIsFlagged() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(diskFree: 900_000_000)).cause, .storage)
    }

    /// The verdict is about processor and memory, so a missing disk reading
    /// must not hold back a clear one.
    func testMissingDiskReadingDoesNotBlockAClearVerdict() {
        XCTAssertEqual(DiagnosisEngine.evaluate(snapshot: snapshot(diskFree: nil)).severity, .healthy)
    }

    private func snapshot(cpu: Double? = 20, memoryUsed: UInt64? = 18_000_000_000, pressure: MemoryPressure = .normal, swap: UInt64? = 0, diskFree: UInt64? = 100_000_000_000, diskTotal: UInt64? = 500_000_000_000, thermal: ThermalLevel = .nominal) -> SystemSnapshot {
        SystemSnapshot(timestamp: Date(), cpuPercent: cpu, memoryUsedBytes: memoryUsed, memoryTotalBytes: 32_000_000_000, memoryPressure: pressure, swapUsedBytes: swap, diskFreeBytes: diskFree, diskTotalBytes: diskTotal, thermal: thermal, processes: [], warnings: [])
    }
}
