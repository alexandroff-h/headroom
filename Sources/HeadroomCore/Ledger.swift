import Foundation

/// The only number Headroom is judged on is how much better the Mac got after
/// the reader did something. That number is *measured*, never predicted:
/// resident memory counts shared pages, so an app's footprint is not what
/// quitting it hands back. Headroom asks the app to quit, waits for the system
/// to settle, and reports the difference it can actually see.

public enum ActionKind: String, Sendable, Codable {
    case quit
    case forceQuit
}

public enum ImpactVerdict: String, Sendable, Codable {
    /// Still inside the settling window. No claim made yet.
    case measuring
    /// A gain above the noise floor.
    case freed
    /// Measured, and the difference was too small to call.
    case noChange
    /// Something else took the room before we looked. Not counted as a win.
    case offset
    /// A reading we needed was unavailable. Said so rather than assumed zero.
    case unknown
}

public struct ActionRecord: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let appName: String
    public let appID: String
    public let kind: ActionKind
    /// What the app was holding when the reader acted. A footprint, not a promise.
    public let footprintBytes: UInt64
    public let footprintCPU: Double
    public var verdict: ImpactVerdict
    /// Positive means the Mac got that much back.
    public var memoryDeltaBytes: Int64?
    public var cpuDelta: Double?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        appName: String,
        appID: String,
        kind: ActionKind,
        footprintBytes: UInt64,
        footprintCPU: Double,
        verdict: ImpactVerdict = .measuring,
        memoryDeltaBytes: Int64? = nil,
        cpuDelta: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.appName = appName
        self.appID = appID
        self.kind = kind
        self.footprintBytes = footprintBytes
        self.footprintCPU = footprintCPU
        self.verdict = verdict
        self.memoryDeltaBytes = memoryDeltaBytes
        self.cpuDelta = cpuDelta
    }

    /// Only a clear, above-noise gain counts toward the recap.
    public var countsAsWin: Bool { verdict == .freed }
    public var memoryWon: UInt64 { countsAsWin ? UInt64(max(0, memoryDeltaBytes ?? 0)) : 0 }
    public var cpuWon: Double { countsAsWin ? max(0, cpuDelta ?? 0) : 0 }
}

public enum Impact {
    /// Below these, a difference is indistinguishable from what the Mac does on
    /// its own in the same twelve seconds. Measured by watching an idle Mac.
    public static let memoryNoiseFloor: Int64 = 64 * 1024 * 1024
    public static let cpuNoiseFloor: Double = 3

    /// How long to wait before looking. Long enough for the app to finish
    /// exiting and for the kernel to return its pages.
    public static let settleSeconds: TimeInterval = 12

    /// Classifies the difference between before and after. Memory leads,
    /// because it is the reading that moves decisively when an app exits;
    /// processor time recovers too but is noisy by nature.
    public static func classify(memoryDelta: Int64?, cpuDelta: Double?) -> ImpactVerdict {
        guard let memoryDelta else {
            guard let cpuDelta else { return .unknown }
            if cpuDelta >= cpuNoiseFloor { return .freed }
            return cpuDelta <= -cpuNoiseFloor ? .offset : .noChange
        }
        if memoryDelta >= memoryNoiseFloor { return .freed }
        if memoryDelta <= -memoryNoiseFloor { return .offset }
        if let cpuDelta, cpuDelta >= cpuNoiseFloor { return .freed }
        return .noChange
    }
}

/// One month's worth of acting on what Headroom showed.
public struct Recap: Sendable, Equatable {
    public struct Repeat: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let count: Int
        public let memoryBytes: UInt64
    }

    public let start: Date
    public let actionCount: Int
    /// Bytes handed back, added up. Each one was measured at the moment it
    /// came back, so this is "returned over the month", not "free right now".
    public let memoryFreedBytes: UInt64
    /// The largest processor gain from a single action.
    ///
    /// Deliberately not a sum. Processor use is a rate: 6% freed on Tuesday
    /// and 11% freed on Friday do not make 17% of anything. The best single
    /// action is a figure that is actually true.
    public let bestCPUGain: Double
    public let records: [ActionRecord]
    /// The things the reader keeps having to close. The most useful page in the
    /// recap, because it points at a habit rather than at a moment.
    public let repeats: [Repeat]

    public var isEmpty: Bool { actionCount == 0 }
}

/// Stores the record on this Mac and nowhere else. No account, no telemetry,
/// and a single call that erases all of it.
public actor ActionLedger {
    private var records: [ActionRecord] = []
    private let fileURL: URL
    private var loaded = false

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Headroom", isDirectory: true)
        self.fileURL = base.appendingPathComponent("actions.json")
    }

    public func all() -> [ActionRecord] {
        load()
        return records
    }

    public func append(_ record: ActionRecord) {
        load()
        records.append(record)
        save()
    }

    public func update(id: UUID, verdict: ImpactVerdict, memoryDeltaBytes: Int64?, cpuDelta: Double?) -> ActionRecord? {
        load()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        records[index].verdict = verdict
        records[index].memoryDeltaBytes = memoryDeltaBytes
        records[index].cpuDelta = cpuDelta
        save()
        return records[index]
    }

    public func erase() {
        records = []
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// The recap for the month containing `date`.
    public func recap(for date: Date = Date(), calendar: Calendar = .current) -> Recap {
        load()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        let inMonth = records.filter { $0.date >= start && $0.date < end }
        return Self.summarise(inMonth, start: start)
    }

    public func lifetime() -> Recap {
        load()
        return Self.summarise(records, start: records.first?.date ?? Date())
    }

    static func summarise(_ records: [ActionRecord], start: Date) -> Recap {
        var counts: [String: (count: Int, bytes: UInt64)] = [:]
        for record in records {
            let existing = counts[record.appName] ?? (0, 0)
            counts[record.appName] = (existing.count + 1, existing.bytes &+ record.memoryWon)
        }
        let repeats = counts
            .filter { $0.value.count >= 2 }
            .map { Recap.Repeat(name: $0.key, count: $0.value.count, memoryBytes: $0.value.bytes) }
            .sorted { $0.count == $1.count ? $0.memoryBytes > $1.memoryBytes : $0.count > $1.count }

        return Recap(
            start: start,
            actionCount: records.count,
            memoryFreedBytes: records.reduce(UInt64(0)) { $0 &+ $1.memoryWon },
            bestCPUGain: records.map(\.cpuWon).max() ?? 0,
            records: records.sorted { $0.date > $1.date },
            repeats: Array(repeats.prefix(4))
        )
    }

    // MARK: Disk

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([ActionRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
