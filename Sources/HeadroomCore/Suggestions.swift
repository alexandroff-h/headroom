import Foundation

/// "Here is how you can improve it." A short, ranked list of things worth
/// doing — never more than three, because a list of ten is a list nobody acts
/// on, and acting is the only thing this app is for.
///
/// Every suggestion names what it would cost you to ignore it, in numbers that
/// were measured. None of them predicts what quitting would free: that claim
/// belongs to `Impact`, after the fact.
public struct Suggestion: Sendable, Identifiable, Equatable {
    public let id: String
    public let appName: String
    /// What the button does, as a sentence. "Quit Slack".
    public let headline: String
    /// Why this one is on the list at all.
    public let reason: String
    public let footprintBytes: UInt64
    public let cpuPercent: Double
    public let score: Double

    public init(id: String, appName: String, headline: String, reason: String, footprintBytes: UInt64, cpuPercent: Double, score: Double) {
        self.id = id
        self.appName = appName
        self.headline = headline
        self.reason = reason
        self.footprintBytes = footprintBytes
        self.cpuPercent = cpuPercent
        self.score = score
    }
}

public enum SuggestionEngine {
    /// A suggestion has to be worth the interruption. Below this — roughly
    /// 800 MB, or a fifth of the processor — quitting something buys the reader
    /// less than the attention the suggestion costs them.
    static let threshold = 0.75
    public static let limit = 3

    /// The exchange rate between a gigabyte and a point of processor use.
    /// All of the processor is worth about four gigabytes, because memory
    /// pressure is what actually makes a Mac feel slow: a pegged core during a
    /// build does not, and ends on its own.
    static let cpuPerGigabyte = 25.0

    /// Idle long enough that the reader has plainly moved on.
    static let idleThreshold: TimeInterval = 10 * 60

    public static func rank(
        apps: [RunningApp],
        snapshot: SystemSnapshot,
        frontmostID: String?,
        idleSeconds: [String: TimeInterval]
    ) -> [Suggestion] {
        // Under memory pressure the expensive mistake is a big idle app; under
        // processor load it is a busy one. The ranking follows the complaint.
        let memoryWeight: Double
        let cpuWeight: Double
        switch snapshot.memoryPressure {
        case .critical: memoryWeight = 2.4
        case .warning: memoryWeight = 1.8
        default: memoryWeight = 1
        }
        if let cpu = snapshot.cpuPercent, cpu >= 80 {
            cpuWeight = 2.0
        } else if let cpu = snapshot.cpuPercent, cpu >= 60 {
            cpuWeight = 1.5
        } else {
            cpuWeight = 1
        }

        let candidates = apps.compactMap { app -> Suggestion? in
            guard app.canQuit, app.id != frontmostID else { return nil }
            let gigabytes = Double(app.memoryBytes) / 1_073_741_824
            let idle = idleSeconds[app.id] ?? 0
            let idleBonus = idle >= idleThreshold ? 1.5 : 1

            let score = (gigabytes * memoryWeight + app.cpuPercent / Self.cpuPerGigabyte * cpuWeight) * idleBonus
            guard score >= threshold else { return nil }

            return Suggestion(
                id: app.id,
                appName: app.name,
                headline: "Quit \(app.name)",
                reason: reason(for: app, idle: idle, pressure: snapshot.memoryPressure),
                footprintBytes: app.memoryBytes,
                cpuPercent: app.cpuPercent,
                score: score
            )
        }

        return Array(candidates.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Every reason names a figure that was measured. None of them says what
    /// quitting would free — that claim is only ever made afterwards.
    private static func reason(for app: RunningApp, idle: TimeInterval, pressure: MemoryPressure) -> String {
        var clauses: [String] = []

        if idle >= idleThreshold {
            clauses.append("you have not switched to it in \(duration(idle))")
        }
        if app.cpuPercent >= 25 {
            clauses.append("it is using \(Int(app.cpuPercent.rounded()))% of the processor in the background")
        } else if app.processCount >= 8 {
            clauses.append("it is spread across \(app.processCount) processes")
        }
        if clauses.isEmpty {
            clauses.append(
                pressure == .warning || pressure == .critical
                    ? "it is the largest thing you could close while memory is tight"
                    : "it is holding more memory than anything else you could close"
            )
        }

        var sentence = clauses.joined(separator: ", and ")
        sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 120 { return "\(minutes / 60) hours" }
        if minutes >= 60 { return "an hour" }
        return "\(max(1, minutes)) minutes"
    }
}
