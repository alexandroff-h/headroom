import Foundation

/// A single, bounded action. AppKit owns the target; this helper owns the
/// evidence required to call its effect a measurement. Time is injected so
/// refusal, missing samples and delayed exits can be tested without quitting apps.
public struct ActionLifecycle: Sendable {
    public enum Status: Sendable, Equatable {
        case idle, preparing, waitingForExit, settling
        case measured, baselineUnavailable, requestRejected, exitTimedOut
        case readingsUnavailable, targetUnavailable, interrupted

        public var isMeasuring: Bool {
            self == .preparing || self == .waitingForExit || self == .settling
        }
    }

    public struct Reading: Sendable {
        public let timestamp: Date
        /// CPU is a rate since the preceding sample. Its entire interval must
        /// belong to the relevant side of the action, not straddle the exit.
        public let intervalStartedAt: Date
        public let memoryBytes: UInt64?
        public let cpuPercent: Double?

        public init(timestamp: Date, intervalStartedAt: Date, memoryBytes: UInt64?, cpuPercent: Double?) {
            self.timestamp = timestamp
            self.intervalStartedAt = intervalStartedAt
            self.memoryBytes = memoryBytes
            self.cpuPercent = cpuPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let verdict: ImpactVerdict
        public let memoryDeltaBytes: Int64?
        public let cpuDelta: Double?
    }

    public static let baselineTimeout: TimeInterval = 12
    public static let exitTimeout: TimeInterval = 20
    public static let afterTimeout: TimeInterval = 12
    /// Three two-second intervals fit inside this window, with scheduler slack.
    public static let sampleFreshness: TimeInterval = 8
    public static let maximumSampleInterval: TimeInterval = 4

    public private(set) var status: Status = .idle
    public private(set) var deadline: Date?
    public private(set) var exitObservedAt: Date?
    public private(set) var outcome: Outcome?
    public var isMeasuring: Bool { status.isMeasuring }

    private var sampleBoundary: Date = .distantFuture
    private var readings: [Reading] = []
    private var baselineMemory: UInt64?
    private var baselineCPU: Double?

    public init() {}

    /// Does not replace an action already in flight.
    @discardableResult
    public mutating func start(at now: Date) -> Bool {
        guard !isMeasuring else { return false }
        self = ActionLifecycle()
        status = .preparing
        sampleBoundary = now
        deadline = now.addingTimeInterval(Self.baselineTimeout)
        return true
    }

    public func canRequest(at now: Date) -> Bool {
        guard status == .preparing, let deadline, now < deadline else { return false }
        let samples = freshReadings(at: now)
        return memoryMedian(samples) != nil || cpuMedian(samples) != nil
    }

    /// Call immediately before sending the OS request, after checking that the
    /// original registered target is still available. It can only happen once.
    @discardableResult
    public mutating func markRequested(at now: Date) -> Bool {
        guard canRequest(at: now) else { return false }
        let samples = freshReadings(at: now)
        baselineMemory = memoryMedian(samples)
        baselineCPU = cpuMedian(samples)
        readings = []
        status = .waitingForExit
        deadline = now.addingTimeInterval(Self.exitTimeout)
        return true
    }

    public mutating func requestRejected() {
        guard status == .waitingForExit else { return }
        finish(.requestRejected)
    }

    public mutating func targetUnavailable() {
        guard status == .preparing else { return }
        finish(.targetUnavailable)
    }

    /// `true` must be the original NSRunningApplication's terminated state,
    /// never absence from an attribution list or a successful request return.
    public mutating func advance(at now: Date, targetHasExited: Bool) {
        guard isMeasuring, let deadline else { return }
        // An exit first seen after the bound cannot rescue a timed-out action.
        guard now < deadline else {
            switch status {
            case .preparing: finish(.baselineUnavailable)
            case .waitingForExit: finish(.exitTimedOut)
            case .settling: finish(.readingsUnavailable)
            default: break
            }
            return
        }
        if status == .waitingForExit, targetHasExited {
            exitObservedAt = now
            status = .settling
            sampleBoundary = now.addingTimeInterval(Impact.settleSeconds)
            self.deadline = sampleBoundary.addingTimeInterval(Self.afterTimeout)
            readings = []
        }
    }

    public mutating func receive(_ reading: Reading, at now: Date) {
        advance(at: now, targetHasExited: false)
        guard status == .preparing || status == .settling,
              reading.intervalStartedAt >= sampleBoundary,
              reading.timestamp > reading.intervalStartedAt,
              reading.timestamp <= now,
              reading.timestamp.timeIntervalSince(reading.intervalStartedAt) <= Self.maximumSampleInterval,
              now.timeIntervalSince(reading.intervalStartedAt) <= Self.sampleFreshness,
              readings.last.map({ reading.intervalStartedAt > $0.intervalStartedAt && reading.timestamp > $0.timestamp }) ?? true
        else { return }

        readings.append(reading)
        readings = Array(freshReadings(at: now).suffix(3))
        guard status == .settling, readings.count == 3 else { return }

        // Missing one of the three values makes that metric unknown. Never
        // compact away nils and call a median of one or two a measurement.
        var memoryDelta: Int64?
        if let before = baselineMemory, let after = memoryMedian(readings) {
            if before >= after {
                memoryDelta = Int64(exactly: before - after)
            } else if let magnitude = Int64(exactly: after - before) {
                memoryDelta = -magnitude
            }
        }
        let cpuDelta = baselineCPU.flatMap { before in cpuMedian(readings).map { before - $0 } }
        let verdict = Impact.classify(memoryDelta: memoryDelta, cpuDelta: cpuDelta)
        status = verdict == .unknown ? .readingsUnavailable : .measured
        outcome = Outcome(verdict: verdict, memoryDeltaBytes: memoryDelta, cpuDelta: cpuDelta)
        deadline = nil
    }

    public mutating func cancel() {
        guard isMeasuring else { return }
        finish(.interrupted)
    }

    private mutating func finish(_ status: Status) {
        self.status = status
        deadline = nil
        outcome = Outcome(verdict: .unknown, memoryDeltaBytes: nil, cpuDelta: nil)
        readings = []
    }

    private func freshReadings(at now: Date) -> [Reading] {
        readings.filter {
            $0.timestamp <= now && now.timeIntervalSince($0.intervalStartedAt) <= Self.sampleFreshness
        }
    }

    private func memoryMedian(_ samples: [Reading]) -> UInt64? {
        let values = samples.compactMap(\.memoryBytes)
        guard samples.count == 3, values.count == 3 else { return nil }
        return values.sorted()[1]
    }

    private func cpuMedian(_ samples: [Reading]) -> Double? {
        let values = samples.compactMap(\.cpuPercent)
        guard samples.count == 3, values.count == 3 else { return nil }
        return values.sorted()[1]
    }
}
