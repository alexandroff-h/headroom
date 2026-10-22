import AppKit
import Observation
import SwiftUI
import HeadroomCore

/// What the reader is looking at.
enum Screen: String, CaseIterable, Identifiable {
    case now
    case apps
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .now: "Now"
        case .apps: "Apps"
        case .progress: "Recap"
        }
    }

}

/// The payoff line: what happened after the reader acted. It is the only claim
/// in the app about an improvement, and it is always a measurement.
struct Payoff: Identifiable, Equatable {
    let id: UUID
    let appName: String
    var verdict: ImpactVerdict
    var memoryDeltaBytes: Int64?
    var cpuDelta: Double?
    /// Upper bound for the current phase, not a promise of an improvement.
    var remaining: Int
    var status: ActionLifecycle.Status = .measured
    var hasConfirmedExit: Bool = false

    var isMeasuring: Bool { verdict == .measuring }

    /// UI contract: use this for in-flight/unknown copy. `.unknown` alone does
    /// not imply an exit; only `hasConfirmedExit` permits an "app quit" claim.
    var statusText: String {
        switch status {
        case .idle, .preparing:
            "Taking fresh readings before asking \(appName) to quit."
        case .waitingForExit:
            "Asked \(appName) to quit. Waiting for it to exit; it may need you to save your work."
        case .settling:
            "\(appName) exited. Waiting for fresh readings after the system settles."
        case .measured:
            "\(appName) exited. Compared three fresh readings before and after."
        case .baselineUnavailable:
            "Fresh baseline readings were unavailable. No quit request was sent to \(appName)."
        case .requestRejected:
            "The quit request to \(appName) was not accepted. No improvement recorded."
        case .exitTimedOut:
            "\(appName) did not finish quitting within the time limit. It may still need you to save your work. No improvement recorded."
        case .readingsUnavailable:
            "\(appName) exited, but fresh comparison readings were unavailable. No improvement recorded."
        case .targetUnavailable:
            "The original running instance of \(appName) was unavailable. No quit request was sent."
        case .interrupted:
            hasConfirmedExit
                ? "\(appName) exited, but measurement was interrupted. No improvement recorded."
                : "Measurement was interrupted. An exit was not confirmed; no improvement recorded."
        }
    }
}

@MainActor
@Observable
final class AppModel {
    // MARK: Readings

    private(set) var snapshot: SystemSnapshot?
    private(set) var diagnosis: Diagnosis?
    private(set) var apps: [RunningApp] = []
    private(set) var suggestions: [Suggestion] = []
    private(set) var warnings: [String] = []

    // MARK: Reader state

    var screen: Screen = .now
    var expandedAppID: String?
    var appQuery = ""
    var focusedAppID: String?
    var payoff: Payoff?
    var recap: Recap?
    var lifetime: Recap?
    var confirmingForceQuit: RunningApp?

    /// While the pointer is inside the list, the order is frozen. A row that
    /// moves out from under the cursor cannot be clicked.
    var pointerInList = false

    /// Apps Headroom has asked to quit and is still waiting on. They stay in
    /// the list, greyed, so the reader can see the request was made.
    private(set) var quittingIDs: Set<String> = []

    /// Disable every quit control, including a previously opened confirmation.
    /// The model also enforces this guard independently of the UI.
    var isMeasuringAction: Bool { measurementTask != nil }

    // MARK: Internals

    private let sampler = SystemSampler()
    private let ledger = ActionLedger()
    private var task: Task<Void, Never>?
    private var interval: Duration = .seconds(2)
    private var measurementTask: Task<Void, Never>?
    private var lifecycle = ActionLifecycle()
    private var isCollecting = false
    private var lastSampleStartedAt: Date?

    private var committedOrder: [String] = []
    private var lastCommit = Date.distantPast
    private var frontmostID: String?
    private var leftFrontAt: [String: Date] = [:]

    // MARK: Lifecycle

    func start() {
        guard task == nil else { return }
        observeWorkspace()
        noteFrontmost()
        Task { await refreshRecaps() }
        task = Task { [weak self] in
            while !Task.isCancelled {
                // The action owns sampling while active, even when the window
                // is hidden. Two loops must not shorten CPU sample intervals.
                if let self, !self.isMeasuringAction { _ = await self.collect() }
                guard let interval = self?.interval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        measurementTask?.cancel()
    }

    /// A window the reader cannot see does not need a two-second heartbeat.
    /// This is driven only by the occlusion notification: reading the occlusion
    /// state inside the sampling loop once throttled Headroom to 30s before the
    /// window had ever appeared, and the processor reading never arrived.
    func setVisible(_ visible: Bool) {
        interval = visible ? .seconds(2) : .seconds(10)
    }

    // MARK: Sampling

    private func collect() async -> ActionLifecycle.Reading? {
        guard !isCollecting, !Task.isCancelled else { return nil }
        isCollecting = true
        defer { isCollecting = false }
        let t0 = Date()
        let intervalStart = lastSampleStartedAt ?? .distantPast
        guard let sample = try? await sampler.sample() else { return nil }
        lastSampleStartedAt = t0
        guard !Task.isCancelled else { return nil }
        let t1 = Date()

        snapshot = sample
        diagnosis = DiagnosisEngine.evaluate(snapshot: sample)
        warnings = sample.warnings

        let launched = Self.launchedApps()
        let grouped = Attribution.group(processes: sample.processes, launched: launched)
        apps = ordered(grouped)
        suggestions = SuggestionEngine.rank(
            apps: apps,
            snapshot: sample,
            frontmostID: frontmostID,
            idleSeconds: idleSeconds()
        )

        let t2 = Date()
        if let log = ProcessInfo.processInfo.environment["HEADROOM_TIMING"] {
            let line = Data(String(
                format: "sample %.1fms  attribute %.1fms  processes %d  apps %d\n",
                t1.timeIntervalSince(t0) * 1000,
                t2.timeIntervalSince(t1) * 1000,
                sample.processes.count,
                apps.count
            ).utf8)
            if let handle = FileHandle(forWritingAtPath: log) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            }
        }
        return ActionLifecycle.Reading(
            timestamp: sample.timestamp,
            intervalStartedAt: intervalStart,
            memoryBytes: sample.memoryUsedBytes,
            cpuPercent: sample.cpuPercent
        )
    }

    // MARK: Order

    /// Processes move every two seconds. A list that re-sorts every two seconds
    /// is a list you cannot click. The order is committed at most every four
    /// seconds, and never while the pointer is inside it.
    private func ordered(_ incoming: [RunningApp]) -> [RunningApp] {
        let ranked = incoming.sorted { left, right in
            if left.memoryBytes == right.memoryBytes { return left.name < right.name }
            return left.memoryBytes > right.memoryBytes
        }
        let incomingOrder = ranked.map(\.id)

        let canCommit = !pointerInList && focusedAppID == nil && expandedAppID == nil && Date().timeIntervalSince(lastCommit) >= 4
        if committedOrder.isEmpty || canCommit {
            committedOrder = incomingOrder
            lastCommit = Date()
            return ranked
        }

        // Keep the committed order, append anything new at the end so a freshly
        // launched app still appears rather than waiting for the next commit.
        let byID = Dictionary(ranked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = committedOrder.compactMap { byID[$0] }
        let known = Set(committedOrder)
        result.append(contentsOf: ranked.filter { !known.contains($0.id) })
        return result
    }

    // MARK: Front-most tracking

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteFrontmost() }
        }
    }

    private func noteFrontmost() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let id = Self.identifier(for: front)
        if let previous = frontmostID, previous != id {
            leftFrontAt[previous] = Date()
        }
        frontmostID = id
        leftFrontAt[id] = nil
    }

    /// Only apps Headroom actually watched leave the front get an idle time.
    /// An app that was never in front since launch has an unknown idle time,
    /// and an unknown stays unknown.
    private func idleSeconds() -> [String: TimeInterval] {
        let now = Date()
        return leftFrontAt.compactMapValues { now.timeIntervalSince($0) }
    }

    private static func identifier(for application: NSRunningApplication) -> String {
        if let path = application.bundleURL?.path { return "bundle:" + path }
        if let identifier = application.bundleIdentifier { return "id:" + identifier }
        return "exec:" + (application.localizedName ?? "pid \(application.processIdentifier)")
    }

    private static func launchedApps() -> [LaunchedApp] {
        NSWorkspace.shared.runningApplications.map { application in
            LaunchedApp(
                pid: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                bundlePath: application.bundleURL?.path,
                hasDockIcon: application.activationPolicy == .regular
            )
        }
    }

    // MARK: Acting

    /// Cooperative by default: the app is asked to quit, so it can save your
    /// work and put its windows back where they were. Headroom never kills a
    /// process behind your back.
    func quit(_ app: RunningApp) {
        guard !isMeasuringAction else { return }
        beginMeasuring(app, kind: .quit)
    }

    /// Only reachable through an explicit UI confirmation, because this is the
    /// one action in Headroom that can lose the reader's work.
    func forceQuit(_ app: RunningApp) {
        guard !isMeasuringAction else { return }
        beginMeasuring(app, kind: .forceQuit)
    }

    private func beginMeasuring(_ app: RunningApp, kind: ActionKind) {
        guard !isMeasuringAction else { return }
        guard app.canQuit, let pid = app.launchedPID,
              pid != ProcessInfo.processInfo.processIdentifier,
              let target = NSRunningApplication(processIdentifier: pid),
              !target.isTerminated, Self.identifier(for: target) == app.id else {
            payoff = Payoff(
                id: UUID(), appName: app.name, verdict: .unknown,
                memoryDeltaBytes: nil, cpuDelta: nil, remaining: 0,
                status: .targetUnavailable
            )
            return
        }
        guard lifecycle.start(at: Date()) else { return }
        let record = ActionRecord(
            appName: app.name,
            appID: app.id,
            kind: kind,
            footprintBytes: app.memoryBytes,
            footprintCPU: app.cpuPercent
        )
        payoff = Payoff(
            id: record.id, appName: app.name, verdict: .measuring,
            memoryDeltaBytes: nil, cpuDelta: nil,
            remaining: Int(ActionLifecycle.baselineTimeout), status: .preparing
        )
        expandedAppID = nil
        // Hold this exact registered instance across every suspension. Never
        // resolve a later process by PID, which could have been reused.
        measurementTask = Task { await runMeasurement(record: record, target: target) }
    }

    private func runMeasurement(record: ActionRecord, target: NSRunningApplication) async {
        // The append completes before any update can run, including an immediate
        // OS rejection. The lock remains held through final ledger persistence.
        await ledger.append(record)
        defer {
            quittingIDs.remove(record.appID)
            measurementTask = nil
        }
        var nextSampleAt = Date.distantPast
        while lifecycle.isMeasuring && !Task.isCancelled {
            let now = Date()
            if lifecycle.status == .preparing, target.isTerminated {
                lifecycle.targetUnavailable()
            }
            lifecycle.advance(at: now, targetHasExited: target.isTerminated)
            if lifecycle.exitObservedAt != nil { quittingIDs.remove(record.appID) }

            if lifecycle.isMeasuring, now >= nextSampleAt {
                if let reading = await collect() {
                    lifecycle.receive(reading, at: Date())
                }
                nextSampleAt = Date().addingTimeInterval(2)
            }
            // Cancellation during an awaited sample must never send a delayed
            // quit request after Headroom stopped.
            guard !Task.isCancelled else { break }
            if lifecycle.canRequest(at: Date()) {
                if target.isTerminated || Self.identifier(for: target) != record.appID {
                    lifecycle.targetUnavailable()
                } else if lifecycle.markRequested(at: Date()) {
                    quittingIDs.insert(record.appID)
                    let accepted = record.kind == .forceQuit ? target.forceTerminate() : target.terminate()
                    if !accepted {
                        lifecycle.requestRejected()
                        quittingIDs.remove(record.appID)
                    }
                }
            }
            publishMeasurement(record: record)
            guard lifecycle.isMeasuring else { break }
            // Yield the main run loop: NSRunningApplication's terminated state
            // updates between turns. Exit/timeout checks do not depend on a
            // successful sampler call or on window visibility.
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { break }
        }
        if Task.isCancelled { lifecycle.cancel() }
        guard let outcome = lifecycle.outcome else { return }
        _ = await ledger.update(
            id: record.id,
            verdict: outcome.verdict,
            memoryDeltaBytes: outcome.memoryDeltaBytes,
            cpuDelta: outcome.cpuDelta
        )
        publishMeasurement(record: record)
        await refreshRecaps()
    }

    private func publishMeasurement(record: ActionRecord) {
        // Dismissing the line never cancels the action or unlocks another quit.
        guard var current = payoff, current.id == record.id else { return }
        current.status = lifecycle.status
        current.hasConfirmedExit = lifecycle.exitObservedAt != nil
        current.verdict = lifecycle.outcome?.verdict ?? .measuring
        current.memoryDeltaBytes = lifecycle.outcome?.memoryDeltaBytes
        current.cpuDelta = lifecycle.outcome?.cpuDelta
        current.remaining = lifecycle.deadline.map {
            max(0, Int($0.timeIntervalSinceNow.rounded(.up)))
        } ?? 0
        payoff = current
    }

    func dismissPayoff() {
        payoff = nil
    }

    // MARK: Record

    func refreshRecaps() async {
        recap = await ledger.recap()
        lifetime = await ledger.lifetime()
    }

    func eraseRecord() {
        Task {
            await ledger.erase()
            await refreshRecaps()
        }
    }

    // MARK: Lookups

    func app(id: String) -> RunningApp? {
        apps.first { $0.id == id }
    }
}
