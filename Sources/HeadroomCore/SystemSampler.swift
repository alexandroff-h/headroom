import Darwin
import Foundation

public actor SystemSampler {
    private struct ProcessBaseline {
        let startSeconds: UInt64
        let startMicroseconds: UInt64
        let cpuTime: UInt64
        let uptime: TimeInterval
        /// A process cannot rename or re-execute itself under the same start
        /// time, so both of these are read once and then carried. Decoding
        /// them again for every process on every sample was the single most
        /// expensive thing Headroom did, which is a poor look on a tool whose
        /// subject is wasted processor time.
        let path: String?
        let name: String
    }

    private var previousTicks: [UInt32]?
    private var previousProcesses: [Int32: ProcessBaseline] = [:]
    private let hostPort = mach_host_self()
    private let timebase: mach_timebase_info_data_t = {
        var information = mach_timebase_info_data_t()
        mach_timebase_info(&information)
        return information
    }()

    public init() {}

    public func resetBaseline() {
        previousTicks = nil
        previousProcesses = [:]
    }

    public func sample() async throws -> SystemSnapshot {
        var warnings: [String] = []
        let cpuPercent = readCPU()
        if cpuPercent == nil {
            warnings.append("Processor sampling is warming up or unavailable. Wait for the next reading.")
        }
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryUsed = readMemory(total: totalMemory)
        if memoryUsed == nil {
            warnings.append("Memory usage is unavailable.")
        }
        let pressure = readPressure()
        if pressure == .unknown {
            warnings.append("macOS did not provide its memory-pressure reading.")
        }
        let swapUsed = readSwap()
        if swapUsed == nil {
            warnings.append("Swap usage is unavailable.")
        }
        let disk = readDisk()
        if disk.free == nil || disk.total == nil {
            warnings.append("Storage capacity for your home volume is unavailable.")
        }
        let processes = readProcesses()
        if processes.isEmpty {
            warnings.append("Process readings are unavailable. Open Activity Monitor to inspect running apps.")
        }
        return SystemSnapshot(
            timestamp: Date(),
            cpuPercent: cpuPercent,
            memoryUsedBytes: memoryUsed,
            memoryTotalBytes: totalMemory,
            memoryPressure: pressure,
            swapUsedBytes: swapUsed,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            thermal: readThermal(),
            processes: processes,
            warnings: warnings
        )
    }

    private func readCPU() -> Double? {
        var information = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            previousTicks = nil
            return nil
        }
        let ticks = withUnsafeBytes(of: information.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        defer { previousTicks = ticks }
        guard let previousTicks, previousTicks.count == ticks.count else { return nil }
        let deltas = zip(ticks, previousTicks).map { current, previous in UInt64(current &- previous) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return min(100, max(0, Double(total - idle) / Double(total) * 100))
    }

    private func readMemory(total: UInt64) -> UInt64? {
        var information = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(hostPort, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS else { return nil }
        let occupiedPages = UInt64(information.active_count) + UInt64(information.inactive_count) + UInt64(information.wire_count) + UInt64(information.compressor_page_count)
        let reclaimablePages = UInt64(information.purgeable_count) + UInt64(information.external_page_count)
        return min(total, (occupiedPages > reclaimablePages ? occupiedPages - reclaimablePages : 0) * UInt64(pageSize))
    }

    private func readPressure() -> MemoryPressure {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .unknown }
        switch value {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }

    private func readSwap() -> UInt64? {
        var information = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &information, &size, nil, 0) == 0 else { return nil }
        return information.xsu_used
    }

    private func readDisk() -> (free: UInt64?, total: UInt64?) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = values.volumeAvailableCapacityForImportantUsage,
           let total = values.volumeTotalCapacity,
           free >= 0, total > 0 {
            return (UInt64(free), UInt64(total))
        }
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) else { return (nil, nil) }
        return ((attributes[.systemFreeSize] as? NSNumber)?.uint64Value, (attributes[.systemSize] as? NSNumber)?.uint64Value)
    }

    private func readThermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    private func readProcesses() -> [ProcessSample] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }
        var identifiers = [Int32](repeating: 0, count: Int(estimatedCount) + 256)
        let identifierBytes = Int32(identifiers.count * MemoryLayout<Int32>.size)
        let actualCount = identifiers.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, identifierBytes)
        }
        guard actualCount > 0 else { return [] }
        var nextBaselines: [Int32: ProcessBaseline] = [:]
        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(actualCount))
        let uptime = ProcessInfo.processInfo.systemUptime
        for identifier in identifiers.prefix(min(Int(actualCount), identifiers.count)) where identifier > 0 {
            var information = proc_taskallinfo()
            let informationSize = Int32(MemoryLayout<proc_taskallinfo>.size)
            let received = proc_pidinfo(identifier, PROC_PIDTASKALLINFO, 0, &information, informationSize)
            guard received == informationSize else { continue }
            let cpuTime = information.ptinfo.pti_total_user &+ information.ptinfo.pti_total_system
            let previous = previousProcesses[identifier]
            let isSameProcess = previous?.startSeconds == information.pbsd.pbi_start_tvsec && previous?.startMicroseconds == information.pbsd.pbi_start_tvusec
            let path = isSameProcess ? previous?.path : readPath(pid: identifier)
            var cpuPercent = 0.0
            if let previous, isSameProcess, uptime > previous.uptime, cpuTime >= previous.cpuTime {
                cpuPercent = CPUTimeMath.percentage(elapsedTicks: cpuTime - previous.cpuTime, elapsedSeconds: uptime - previous.uptime, timebaseNumerator: timebase.numer, timebaseDenominator: timebase.denom)
            }
            let name: String
            if isSameProcess, let carried = previous?.name {
                name = carried
            } else {
                var decoded = withUnsafeBytes(of: information.pbsd.pbi_name) { bytes in
                    String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                }
                if decoded.isEmpty {
                    decoded = withUnsafeBytes(of: information.pbsd.pbi_comm) { bytes in
                        String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                    }
                }
                name = decoded.isEmpty ? "Process \(identifier)" : decoded
            }
            nextBaselines[identifier] = ProcessBaseline(startSeconds: information.pbsd.pbi_start_tvsec, startMicroseconds: information.pbsd.pbi_start_tvusec, cpuTime: cpuTime, uptime: uptime, path: path, name: name)
            samples.append(ProcessSample(pid: identifier, parentPID: Int32(clamping: information.pbsd.pbi_ppid), uid: information.pbsd.pbi_uid, name: name, executablePath: path, cpuPercent: max(0, cpuPercent), memoryBytes: information.ptinfo.pti_resident_size))
        }
        previousProcesses = nextBaselines
        return samples.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private func readPath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

enum CPUTimeMath {
    static func percentage(elapsedTicks: UInt64, elapsedSeconds: Double, timebaseNumerator: UInt32, timebaseDenominator: UInt32) -> Double {
        guard elapsedSeconds > 0, timebaseDenominator > 0 else { return 0 }
        let nanoseconds = Double(elapsedTicks) * Double(timebaseNumerator) / Double(timebaseDenominator)
        return nanoseconds / 1_000_000_000 / elapsedSeconds * 100
    }
}
