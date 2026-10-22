import AppKit
import XCTest
@testable import HeadroomCore

/// The minimum-width verdict block allows two lines for the title and two for the
/// explanation. These tests hold the copy to that reservation, so no string can
/// quietly start truncating on a Mac nobody tested on.
///
/// The measurements use Avenir Next at the actual 680pt minimum window
/// minus two 36pt gutters. Titles may wrap rather than truncate.
final class DiagnosisCopyTests: XCTestCase {
    private let verdictSize: CGFloat = 38
    private let verdictTracking: CGFloat = -1.4
    private let verdictMeasure: CGFloat = 608
    private let bodySize: CGFloat = 13
    private let bodyMeasure: CGFloat = 608

    func testEveryVerdictFitsTwoLinesAtMinimumWindowWidth() {
        for diagnosis in allDiagnoses() {
            XCTAssertLessThanOrEqual(lineCount(diagnosis.title, size: verdictSize, width: verdictMeasure, name: "AvenirNext-DemiBold"), 2)
        }
    }

    func testEveryExplanationFitsTwoLines() {
        for diagnosis in allDiagnoses() {
            let lines = lineCount(diagnosis.explanation, size: bodySize, width: bodyMeasure)
            XCTAssertLessThanOrEqual(
                lines, 2,
                "“\(diagnosis.explanation)” wraps to \(lines) lines in a \(Int(bodyMeasure))pt column"
            )
        }
    }

    func testEvidenceIsNeverEmpty() {
        for diagnosis in allDiagnoses() {
            XCTAssertFalse(diagnosis.evidence.isEmpty, "\(diagnosis.cause) produced no evidence line")
        }
    }

    // MARK: Fixtures

    private func allDiagnoses() -> [Diagnosis] {
        [
            snapshot(thermal: .serious),
            snapshot(thermal: .critical),
            snapshot(pressure: .warning),
            snapshot(pressure: .critical),
            snapshot(cpu: 90),
            snapshot(cpu: 99),
            snapshot(diskFree: 4_000_000_000),
            snapshot(diskFree: 500_000_000),
            snapshot(cpu: nil),
            snapshot(pressure: .unknown),
            snapshot(),
        ].map(DiagnosisEngine.evaluate(snapshot:))
    }

    private func snapshot(
        cpu: Double? = 20,
        pressure: MemoryPressure = .normal,
        thermal: ThermalLevel = .nominal,
        diskFree: UInt64 = 300_000_000_000
    ) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuPercent: cpu,
            memoryUsedBytes: 12_000_000_000,
            memoryTotalBytes: 24_000_000_000,
            memoryPressure: pressure,
            swapUsedBytes: 0,
            diskFreeBytes: diskFree,
            diskTotalBytes: 500_000_000_000,
            thermal: thermal,
            processes: [],
            warnings: []
        )
    }

    // MARK: Measurement

    private func measuredWidth(_ text: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .kern: tracking,
        ]
        return (text as NSString).size(withAttributes: attributes).width
    }

    private func lineCount(_ text: String, size: CGFloat, width: CGFloat, name: String = "AvenirNext-Regular") -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)])
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var lines = 0
        var index = 0
        let glyphs = manager.glyphRange(for: container)
        while index < glyphs.length {
            var lineRange = NSRange()
            manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
            index = NSMaxRange(lineRange)
            lines += 1
        }
        return lines
    }
}
