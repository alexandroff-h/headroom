import XCTest
@testable import HeadroomCore

/// The suggestion list is the product. If it offers something the reader should
/// not close, or buries the thing they should, nothing else in the app matters.
final class SuggestionTests: XCTestCase {
    func testNeverMoreThanThree() {
        let apps = (1...10).map { app(id: "a\($0)", name: "App \($0)", memory: UInt64($0) * 1_000_000_000) }
        XCTAssertEqual(SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]).count, 3)
    }

    func testTheAppInFrontIsNeverSuggested() {
        let apps = [app(id: "front", name: "Xcode", memory: 8_000_000_000)]
        XCTAssertTrue(SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: "front", idleSeconds: [:]).isEmpty)
    }

    func testMacOSIsNeverSuggested() {
        let apps = [app(id: "sys", name: "Spotlight", memory: 9_000_000_000, kind: .system, launchedPID: 42)]
        XCTAssertTrue(SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]).isEmpty)
    }

    func testSomethingWithNoAppToAskIsNeverSuggested() {
        let apps = [app(id: "daemon", name: "something", memory: 9_000_000_000, launchedPID: nil)]
        XCTAssertTrue(SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]).isEmpty)
    }

    func testSomethingSmallIsNotWorthTheInterruption() {
        let apps = [app(id: "small", name: "Notes", memory: 120_000_000, cpu: 0.4)]
        XCTAssertTrue(SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]).isEmpty)
    }

    /// Under memory pressure the expensive mistake is a large idle app; under
    /// processor load it is a busy one. The ranking has to follow the complaint.
    func testRankingFollowsTheComplaint() {
        let apps = [
            app(id: "big", name: "Docker", memory: 4_000_000_000, cpu: 1),
            app(id: "busy", name: "Compiler", memory: 400_000_000, cpu: 95),
        ]

        let underMemoryPressure = SuggestionEngine.rank(apps: apps, snapshot: snapshot(pressure: .critical), frontmostID: nil, idleSeconds: [:])
        XCTAssertEqual(underMemoryPressure.first?.appName, "Docker")

        let underLoad = SuggestionEngine.rank(apps: apps, snapshot: snapshot(cpu: 96), frontmostID: nil, idleSeconds: [:])
        XCTAssertEqual(underLoad.first?.appName, "Compiler")
    }

    func testBeingIdleMovesSomethingUpTheList() {
        let apps = [
            app(id: "active", name: "Active", memory: 1_400_000_000),
            app(id: "idle", name: "Idle", memory: 1_200_000_000),
        ]
        let ranked = SuggestionEngine.rank(
            apps: apps,
            snapshot: snapshot(),
            frontmostID: nil,
            idleSeconds: ["idle": 3 * 3600]
        )
        XCTAssertEqual(ranked.first?.appName, "Idle")
        XCTAssertTrue(ranked[0].reason.contains("3 hours"), ranked[0].reason)
    }

    /// Every reason has to read as a sentence, because it is shown as one.
    func testEveryReasonIsASentence() {
        let apps = [
            app(id: "a", name: "Big", memory: 3_000_000_000),
            app(id: "b", name: "Busy", memory: 900_000_000, cpu: 60),
            app(id: "c", name: "Many", memory: 900_000_000, processCount: 14),
        ]
        for suggestion in SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]) {
            XCTAssertTrue(suggestion.reason.hasSuffix("."), suggestion.reason)
            let first = suggestion.reason.first!
            XCTAssertTrue(first.isUppercase, "“\(suggestion.reason)” does not start a sentence")
        }
    }

    /// No suggestion may claim that quitting will free anything. That claim is
    /// only ever made afterwards, from a measurement.
    func testNoSuggestionPromisesAnOutcome() {
        let apps = [app(id: "a", name: "Big", memory: 3_000_000_000)]
        for suggestion in SuggestionEngine.rank(apps: apps, snapshot: snapshot(), frontmostID: nil, idleSeconds: [:]) {
            let text = (suggestion.reason + " " + suggestion.headline).lowercased()
            for promise in ["will free", "would free", "frees", "you will get", "recover"] {
                XCTAssertFalse(text.contains(promise), "“\(text)” promises an outcome")
            }
        }
    }

    // MARK: Fixtures

    private func app(
        id: String,
        name: String,
        memory: UInt64,
        cpu: Double = 1,
        kind: AppKind = .app,
        processCount: Int = 1,
        launchedPID: Int32? = 10
    ) -> RunningApp {
        RunningApp(
            id: id,
            name: name,
            bundleIdentifier: "test." + id,
            bundlePath: "/Applications/\(name).app",
            kind: kind,
            explanation: "",
            origin: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            processes: (0..<processCount).map {
                ProcessSample(pid: Int32(1000 + $0), parentPID: 1, uid: 501, name: name, executablePath: nil, cpuPercent: 0, memoryBytes: 0)
            },
            launchedPID: launchedPID
        )
    }

    private func snapshot(cpu: Double? = 20, pressure: MemoryPressure = .normal) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: Date(),
            cpuPercent: cpu,
            memoryUsedBytes: 12_000_000_000,
            memoryTotalBytes: 24_000_000_000,
            memoryPressure: pressure,
            swapUsedBytes: 0,
            diskFreeBytes: 300_000_000_000,
            diskTotalBytes: 500_000_000_000,
            thermal: .nominal,
            processes: [],
            warnings: []
        )
    }
}
