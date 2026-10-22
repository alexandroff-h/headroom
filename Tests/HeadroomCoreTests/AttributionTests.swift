import XCTest
@testable import HeadroomCore

/// Attribution is the answer to "what IS this thing", so these tests are about
/// the cases where a process name lies: helpers that belong to an app, tools an
/// app started, and bundles named after a version number.
final class AttributionTests: XCTestCase {
    func testHelpersCollapseOntoTheirApp() {
        let apps = Attribution.group(
            processes: [
                process(pid: 100, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", memory: 400_000_000),
                process(pid: 101, parent: 100, name: "Google Chrome Helper (Renderer)", path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/120/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", memory: 300_000_000),
                process(pid: 102, parent: 100, name: "Google Chrome Helper (GPU)", path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/120/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)", memory: 200_000_000),
            ],
            launched: [launched(pid: 100, name: "Google Chrome", bundle: "/Applications/Google Chrome.app")]
        )

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].name, "Google Chrome")
        XCTAssertEqual(apps[0].processCount, 3)
        XCTAssertEqual(apps[0].memoryBytes, 900_000_000)
        XCTAssertEqual(apps[0].launchedPID, 100)
    }

    /// The quit request must reach the app, never one of its helpers, or the
    /// app respawns the helper and nothing happens.
    func testQuitAddressesTheAppRatherThanAHelper() {
        let apps = Attribution.group(
            processes: [
                process(pid: 100, name: "Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                process(pid: 101, parent: 100, name: "Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Helper.app/Contents/MacOS/Chrome Helper"),
            ],
            launched: [
                launched(pid: 101, name: "Google Chrome Helper", bundle: "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Helper.app", dockIcon: false),
                launched(pid: 100, name: "Google Chrome", bundle: "/Applications/Google Chrome.app", dockIcon: true),
            ]
        )

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].launchedPID, 100)
        XCTAssertTrue(apps[0].canQuit)
    }

    /// A `node` with no bundle of its own belongs under whatever started it.
    func testBundlelessProcessesInheritFromTheirParent() {
        let apps = Attribution.group(
            processes: [
                process(pid: 200, name: "Code", path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", memory: 100),
                process(pid: 201, parent: 200, name: "node", path: "/opt/homebrew/bin/node", memory: 50),
                process(pid: 202, parent: 201, name: "esbuild", path: nil, memory: 25),
            ],
            launched: [launched(pid: 200, name: "Visual Studio Code", bundle: "/Applications/Visual Studio Code.app")]
        )

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].processCount, 3)
        XCTAssertTrue(apps[0].explanation.contains("started by it"))
    }

    /// Everything descends from launchd. If that counted, the whole Mac would
    /// be one row.
    func testAttributionStopsAtLaunchd() {
        let apps = Attribution.group(
            processes: [
                process(pid: 1, parent: 0, name: "launchd", path: "/sbin/launchd"),
                process(pid: 300, parent: 1, name: "mystery", path: nil),
            ],
            launched: []
        )
        XCTAssertEqual(apps.count, 2)
    }

    func testAVersionNumberIsNotAName() {
        let apps = Attribution.group(
            processes: [process(pid: 400, name: "helper", path: "/Users/x/Library/Application Support/Claude/claude-code/2.1.308/a93ded4b/2.1.308.app/Contents/MacOS/helper")],
            launched: []
        )
        XCTAssertEqual(apps[0].name, "claude-code")
    }

    /// `.appex` is an extension, not an app. A substring search for ".app"
    /// truncates one into a path that does not exist.
    func testAnAppExtensionIsNotMistakenForAnApp() {
        XCTAssertEqual(
            Attribution.outermostBundle(in: "/Applications/Mail.app/Contents/PlugIns/Thing.appex/Contents/MacOS/Thing"),
            "/Applications/Mail.app"
        )
        XCTAssertNil(Attribution.outermostBundle(in: "/Library/Extensions/Thing.appex/Contents/MacOS/Thing"))
    }

    func testSystemProcessesAreNotOfferedForQuitting() {
        let apps = Attribution.group(
            processes: [process(pid: 500, name: "mds_stores", path: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mds_stores")],
            launched: []
        )
        XCTAssertEqual(apps[0].kind, .system)
        XCTAssertFalse(apps[0].canQuit)
    }

    /// The catalogue exists to explain cryptic executables, not to rename apps
    /// that already have a bundle to take a name from.
    func testACataloguedHelperKeepsItsBundleName() {
        let apps = Attribution.group(
            processes: [process(pid: 600, name: "SourceKitService", path: "/Applications/Xcode.app/Contents/SharedFrameworks/SourceKit.framework/Versions/A/XPCServices/SourceKitService.xpc/Contents/MacOS/SourceKitService")],
            launched: []
        )
        XCTAssertEqual(apps[0].name, "Xcode")
        XCTAssertTrue(apps[0].explanation.contains("completions"))
    }

    func testAnUnidentifiedProcessSaysSo() {
        let apps = Attribution.group(
            processes: [process(pid: 700, parent: 1, name: "weird-thing", path: nil)],
            launched: []
        )
        XCTAssertEqual(apps[0].kind, .unidentified)
        XCTAssertTrue(apps[0].explanation.contains("could not tell"))
    }

    /// The list redraws only the rows that visibly changed, which only works if
    /// equality is measured at the precision a row actually shows.
    func testRowsThatWouldDrawTheSameAreEqual() {
        let drifted = row(memory: 2_400_000_000, cpu: 12.4)
        XCTAssertEqual(row(memory: 2_400_050_000, cpu: 12.3), drifted)
        XCTAssertNotEqual(row(memory: 2_600_000_000, cpu: 12.3), drifted)
        XCTAssertNotEqual(row(memory: 2_400_050_000, cpu: 14.0), drifted)
    }

    /// Scaling into a display unit without keeping the unit makes 2.3 MB and
    /// 2.3 GB the same number.
    func testMemoryBucketsKeepTheirUnit() {
        XCTAssertNotEqual(
            RunningApp.displayedMemory(2_400_000),
            RunningApp.displayedMemory(2_400_000_000)
        )
    }

    private func row(memory: UInt64, cpu: Double) -> RunningApp {
        RunningApp(
            id: "x", name: "X", bundleIdentifier: nil, bundlePath: nil, kind: .app,
            explanation: "", origin: nil, cpuPercent: cpu, memoryBytes: memory,
            processes: [process(pid: 1, name: "X", path: nil, memory: memory)],
            launchedPID: 1
        )
    }

    // MARK: Fixtures

    private func process(pid: Int32, parent: Int32 = 1, name: String, path: String?, memory: UInt64 = 1000, cpu: Double = 1) -> ProcessSample {
        ProcessSample(pid: pid, parentPID: parent, uid: 501, name: name, executablePath: path, cpuPercent: cpu, memoryBytes: memory)
    }

    private func launched(pid: Int32, name: String, bundle: String?, dockIcon: Bool = true) -> LaunchedApp {
        LaunchedApp(pid: pid, bundleIdentifier: "test." + name, localizedName: name, bundlePath: bundle, hasDockIcon: dockIcon)
    }
}
