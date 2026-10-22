import Foundation

public enum MemoryPressure: String, Sendable, Codable {
    case unknown, normal, warning, critical
}

public enum ThermalLevel: String, Sendable, Codable {
    case unknown, nominal, fair, serious, critical
}

public struct ProcessSample: Sendable, Identifiable, Codable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parentPID: Int32
    public let uid: UInt32
    public let name: String
    public let executablePath: String?
    public let cpuPercent: Double
    public let memoryBytes: UInt64

    public init(pid: Int32, parentPID: Int32, uid: UInt32, name: String, executablePath: String?, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.name = name
        self.executablePath = executablePath
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct SystemSnapshot: Sendable, Codable {
    public let timestamp: Date
    public let cpuPercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64
    public let memoryPressure: MemoryPressure
    public let swapUsedBytes: UInt64?
    public let diskFreeBytes: UInt64?
    public let diskTotalBytes: UInt64?
    public let thermal: ThermalLevel
    public let processes: [ProcessSample]
    public let warnings: [String]

    public init(timestamp: Date, cpuPercent: Double?, memoryUsedBytes: UInt64?, memoryTotalBytes: UInt64, memoryPressure: MemoryPressure, swapUsedBytes: UInt64?, diskFreeBytes: UInt64?, diskTotalBytes: UInt64?, thermal: ThermalLevel, processes: [ProcessSample], warnings: [String]) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressure = memoryPressure
        self.swapUsedBytes = swapUsedBytes
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.thermal = thermal
        self.processes = processes
        self.warnings = warnings
    }
}

public enum DiagnosisSeverity: String, Sendable, Codable {
    case healthy, attention, critical
}

public enum DiagnosisCause: String, Sendable, Codable {
    case none, cpu, memory, thermal, storage
}

public struct Diagnosis: Sendable, Codable {
    public let severity: DiagnosisSeverity
    public let title: String
    public let explanation: String
    public let cause: DiagnosisCause
    public let evidence: String

    public init(severity: DiagnosisSeverity, title: String, explanation: String, cause: DiagnosisCause, evidence: String) {
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.cause = cause
        self.evidence = evidence
    }
}
