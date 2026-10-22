import XCTest
@testable import HeadroomCore

final class CPUTimeMathTests: XCTestCase {
    func testAppleSiliconMachTicksBecomeOneCorePercent() {
        XCTAssertEqual(CPUTimeMath.percentage(elapsedTicks: 24_000_000, elapsedSeconds: 1, timebaseNumerator: 125, timebaseDenominator: 3), 100, accuracy: 0.001)
    }

    func testMultipleCoresCanExceedOneHundredPercent() {
        XCTAssertEqual(CPUTimeMath.percentage(elapsedTicks: 48_000_000, elapsedSeconds: 1, timebaseNumerator: 125, timebaseDenominator: 3), 200, accuracy: 0.001)
    }

    func testIntelNanosecondTimebase() {
        XCTAssertEqual(CPUTimeMath.percentage(elapsedTicks: 500_000_000, elapsedSeconds: 2, timebaseNumerator: 1, timebaseDenominator: 1), 25, accuracy: 0.001)
    }

    func testNonpositiveIntervalHasNoCPUReading() {
        XCTAssertEqual(CPUTimeMath.percentage(elapsedTicks: 100, elapsedSeconds: 0, timebaseNumerator: 125, timebaseDenominator: 3), 0)
    }
}
