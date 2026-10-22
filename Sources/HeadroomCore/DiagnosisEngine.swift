import Foundation

/// "Here is your performance", in one sentence a person would say out loud.
///
/// The verdict's job is to hand the reader straight to the list of things they
/// could do about it, so each explanation ends pointing downward. Nothing here
/// invents a score: every branch names the reading that put it there.
public enum DiagnosisEngine {
    public static func evaluate(snapshot: SystemSnapshot) -> Diagnosis {
        if snapshot.thermal == .critical || snapshot.thermal == .serious {
            return Diagnosis(
                severity: snapshot.thermal == .critical ? .critical : .attention,
                title: "Your Mac is running hot.",
                explanation: "macOS is limiting performance to cool down. Pausing a demanding task can give it a chance to recover.",
                cause: .thermal,
                evidence: "Thermal state: \(snapshot.thermal.rawValue)"
            )
        }
        if snapshot.memoryPressure == .warning || snapshot.memoryPressure == .critical {
            return Diagnosis(
                severity: snapshot.memoryPressure == .critical ? .critical : .attention,
                title: "Memory is tight.",
                explanation: "macOS is working harder to manage memory. Closing an app you aren’t using can ease the pressure.",
                cause: .memory,
                evidence: "Memory pressure: \(snapshot.memoryPressure.rawValue)"
            )
        }
        if let cpu = snapshot.cpuPercent, cpu >= 85 {
            return Diagnosis(
                severity: cpu >= 97 ? .critical : .attention,
                title: "Something is working your Mac hard.",
                explanation: "Nearly all the processing capacity is spoken for. A build, an export or an update doing this is normal and will end on its own.",
                cause: .cpu,
                evidence: "Processor use: \(Int(cpu.rounded()))% across all cores"
            )
        }
        // Storage earns a place here only when it is low enough to stop macOS
        // swapping, which is a performance problem. A merely full disk is not.
        if let free = snapshot.diskFreeBytes, free < 5_000_000_000 {
            return Diagnosis(
                severity: free < 1_000_000_000 ? .critical : .attention,
                title: "There is no room left to work in.",
                explanation: "macOS has little free storage for temporary files and swap. Freeing space can help it keep up.",
                cause: .storage,
                evidence: "\(ByteCountFormatter.string(fromByteCount: Int64(clamping: free), countStyle: .file)) free on your home volume"
            )
        }
        if snapshot.cpuPercent == nil {
            return Diagnosis(
                severity: .attention,
                title: "Getting a feel for your Mac.",
                explanation: "Processor use needs two readings before it means anything. Everything else below is already live.",
                cause: .none,
                evidence: snapshot.warnings.first ?? "Waiting for a second processor reading"
            )
        }
        if snapshot.memoryPressure == .unknown || snapshot.memoryUsedBytes == nil {
            return Diagnosis(
                severity: .attention,
                title: "Part of the picture is missing.",
                explanation: "A memory reading macOS normally provides did not arrive, so Headroom cannot promise everything is clear.",
                cause: .none,
                evidence: snapshot.warnings.first ?? "A system reading is unavailable"
            )
        }
        return Diagnosis(
            severity: .healthy,
            title: "Your Mac has room.",
            explanation: "Nothing is competing for the processor or for memory right now. Anything below is yours to close, not something you need to.",
            cause: .none,
            evidence: "No processor or memory pressure in this reading"
        )
    }
}
