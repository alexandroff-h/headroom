import SwiftUI
import HeadroomCore

/// A record of measured changes, not a prediction of what closing an app buys.
struct ProgressScreen: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingErase = false

    private var recap: Recap? { model.recap }
    private var hasRecord: Bool {
        model.lifetime?.isEmpty == false || recap?.isEmpty == false
    }

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel(monthName)

                Text("Room you made.")
                    .type(Face.verdict)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("What changed after you asked an app to close.")
                    .type(Face.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.xxl)

            ProgressFigures(recap: recap)
                .padding(.top, Space.xl)

            if let recap {
                if recap.isEmpty {
                    EmptyProgress(hasEarlierRecord: model.lifetime?.isEmpty == false) {
                        model.screen = .now
                    }
                } else {
                    History(records: recap.records)
                        .padding(.top, Space.xxl)

                    if !recap.repeats.isEmpty {
                        Repeats(repeats: recap.repeats)
                            .padding(.top, Space.xxl)
                    }
                }
            } else {
                loading
            }

            // Erasing applies to the whole ledger, even when this month is empty.
            Footer(
                lifetime: model.lifetime,
                canErase: hasRecord,
                confirmingErase: $confirmingErase
            )
            .padding(.top, Space.xxl)
        }
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
        .task { await model.refreshRecaps() }
        .confirmationDialog(
            "Erase everything Headroom has recorded?",
            isPresented: $confirmingErase,
            titleVisibility: .visible
        ) {
            Button("Erase", role: .destructive) { model.eraseRecord() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every action and every measurement is deleted from this Mac. There is no copy anywhere else.")
        }
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: recap?.start ?? Date())
    }

    private var loading: some View {
        HStack(alignment: .center, spacing: Space.m) {
            if reduceMotion {
                Image(systemName: "clock")
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Reading your record.")
                    .type(Face.section)
                    .foregroundStyle(Ink.primary)
                Text("Loading the actions saved on this Mac.")
                    .type(Face.body)
                    .foregroundStyle(Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.xxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Three measures, one surface

private struct ProgressFigures: View {
    let recap: Recap?

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            HStack(alignment: .top, spacing: Space.xl) {
                Figure(
                    label: "Memory back",
                    measure: memory,
                    detail: "Total measured this month"
                )
                Figure(
                    label: "Best CPU gain",
                    measure: processor,
                    detail: "From a single action"
                )
                Figure(
                    label: "Actions taken",
                    measure: recap.map { Measure.count($0.actionCount) } ?? .unavailable,
                    detail: "Recorded this month"
                )
            }
            .padding(.vertical, Space.xl)
            Rule()
        }
    }

    // Missing measurements are not zero. The aggregate itself always comes
    // from the ledger: memory is summed, processor gain is a single maximum.
    private var memory: Measure {
        guard let recap, recap.records.contains(where: {
            $0.verdict != .measuring && $0.verdict != .unknown && $0.memoryDeltaBytes != nil
        }) else { return .unavailable }
        return Measure.memory(recap.memoryFreedBytes)
    }

    private var processor: Measure {
        guard let recap, recap.records.contains(where: {
            $0.verdict != .measuring && $0.verdict != .unknown && $0.cpuDelta?.isFinite == true
        }) else { return .unavailable }
        return Measure.percent(recap.bestCPUGain, digits: 1)
    }

    private struct Figure: View {
        let label: String
        let measure: Measure
        let detail: String
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: Space.s) {
                MicroLabel(label)
                    .fixedSize(horizontal: false, vertical: true)
                Reading(measure: measure, style: Face.figure, unitStyle: Face.body)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : Motion.reading, value: measure)
                Text(detail)
                    .type(Face.caption)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), \(measure.spoken). \(detail).")
        }
    }
}

// MARK: - A record waiting to begin

private struct EmptyProgress: View {
    let hasEarlierRecord: Bool
    let showNow: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Space.l) {
            ReceiptDrawing()
                .stroke(
                    contrast == .increased ? Ink.tertiary : Ink.ruleStrong,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 48, height: 60)
                .accessibilityHidden(true)

            VStack(spacing: Space.s) {
                Text("Your next good decision starts here.")
                    .type(Face.section)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(hasEarlierRecord
                     ? "No actions recorded this month. Your next measured result will appear here."
                     : "Close an app from Now. Headroom will measure the change and keep it here.")
                    .type(Face.body)
                    .foregroundStyle(Ink.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Metrics.proseMeasure)
            .fixedSize(horizontal: false, vertical: true)

            Button("See what you can close", action: showNow)
                .buttonStyle(ActionStyle())
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.l)
    }

    /// An empty receipt and three rules. Decoration, never a sample record.
    private struct ReceiptDrawing: Shape {
        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
            }

            return Path { path in
                path.move(to: point(0.12, 0.06))
                path.addLine(to: point(0.88, 0.06))
                path.addLine(to: point(0.88, 0.94))
                path.addLine(to: point(0.69, 0.86))
                path.addLine(to: point(0.5, 0.94))
                path.addLine(to: point(0.31, 0.86))
                path.addLine(to: point(0.12, 0.94))
                path.closeSubpath()

                let rulePositions: [CGFloat] = [0.28, 0.44, 0.60]
                for y in rulePositions {
                    path.move(to: point(0.29, y))
                    path.addLine(to: point(y == 0.60 ? 0.56 : 0.71, y))
                }
            }
        }
    }
}

// MARK: - The measured record

private struct History: View {
    let records: [ActionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Your actions")
                .accessibilityAddTraits(.isHeader)

            ForEach(grouped, id: \.key) { group in
                MicroLabel(group.key)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.l)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(group.records) { record in
                        Entry(record: record, isLast: record.id == group.records.last?.id)
                    }
                }
            }
        }
    }

    private var grouped: [(key: String, records: [ActionRecord])] {
        let calendar = Calendar.current
        let now = Date()
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        var buckets: [(key: String, records: [ActionRecord])] = []

        for record in records.sorted(by: { $0.date > $1.date }) {
            let key: String
            if calendar.isDateInToday(record.date) {
                key = "Today"
            } else if calendar.isDateInYesterday(record.date) {
                key = "Yesterday"
            } else if thisWeek?.contains(record.date) == true {
                key = "This week"
            } else if lastWeek?.contains(record.date) == true {
                key = "Last week"
            } else {
                key = "Earlier this month"
            }

            if let index = buckets.firstIndex(where: { $0.key == key }) {
                buckets[index].records.append(record)
            } else {
                buckets.append((key, [record]))
            }
        }
        return buckets
    }

    private struct Entry: View {
        let record: ActionRecord
        let isLast: Bool
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(hasGain ? Ink.gain : Ink.tertiary)
                    .frame(width: 16, height: 20)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                        subject.fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: Space.m)
                        result.fixedSize(horizontal: true, vertical: true)
                            .multilineTextAlignment(.trailing)
                        time
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            subject
                            Spacer(minLength: Space.s)
                            time
                        }
                        result
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : Space.xl)
            .background(alignment: .topLeading) {
                if !isLast {
                    Rectangle()
                        .fill(Ink.ruleStrong)
                        .frame(width: contrast == .increased ? 1.5 : 1)
                        .padding(.leading, contrast == .increased ? 7.25 : 7.5)
                        .padding(.top, Space.xl)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(record.appName). \(action). \(outcome). \(record.date.formatted(date: .complete, time: .shortened)).")
        }

        private var subject: some View {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(record.appName)
                    .type(Face.row)
                    .foregroundStyle(Ink.primary)
                Text(action)
                    .type(Face.caption)
                    .foregroundStyle(Ink.tertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        private var result: some View {
            Text(outcome)
                .type(Face.reading)
                .foregroundStyle(hasGain ? Ink.gain : Ink.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }

        private var time: some View {
            Text(record.date, format: .dateTime.hour().minute())
                .type(Face.caption)
                .foregroundStyle(Ink.tertiary)
                .monospacedDigit()
                .fixedSize()
                .help(record.date.formatted(date: .complete, time: .shortened))
        }

        private var action: String {
            record.kind == .forceQuit ? "Force quit requested" : "Quit requested"
        }

        private var hasGain: Bool {
            record.countsAsWin && (record.memoryWon > 0 || record.cpuWon >= Impact.cpuNoiseFloor)
        }

        private var outcome: String {
            switch record.verdict {
            case .freed:
                var parts: [String] = []
                if record.memoryWon > 0 {
                    parts.append("\(Measure.memory(record.memoryWon).inline) memory back")
                }
                if record.cpuWon >= Impact.cpuNoiseFloor {
                    parts.append("\(Measure.percent(record.cpuWon, digits: 1).inline) CPU gain")
                }
                return parts.isEmpty ? "Measurement unavailable" : parts.joined(separator: "\n")
            case .noChange:
                return "No measurable change"
            case .offset:
                if let memory = record.memoryDeltaBytes, memory <= -Impact.memoryNoiseFloor {
                    return "\(Measure.memory(memory.magnitude).inline) more memory used"
                }
                if let cpu = record.cpuDelta, cpu <= -Impact.cpuNoiseFloor {
                    return "\(Measure.percent(-cpu, digits: 1).inline) more CPU used"
                }
                return "Usage was higher"
            case .unknown:
                return "Measurement unavailable"
            case .measuring:
                return "Measuring…"
            }
        }

        private var symbol: String {
            switch record.verdict {
            case .freed: hasGain ? "checkmark.circle" : "questionmark.circle"
            case .noChange: "equal.circle"
            case .offset: "arrow.up.circle"
            case .unknown: "questionmark.circle"
            case .measuring: "clock"
            }
        }
    }
}

// MARK: - Patterns in the actual record

private struct Repeats: View {
    let repeats: [Recap.Repeat]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("More than once")
                .accessibilityAddTraits(.isHeader)

            Text("Apps you asked to close more than once this month.")
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)

            ForEach(repeats) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    Text(entry.name)
                        .type(Face.row)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.m)
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Text("\(entry.count) actions")
                            .type(Face.reading)
                            .foregroundStyle(Ink.primary)
                        Text(entry.memoryBytes > 0
                             ? "\(Measure.memory(entry.memoryBytes).inline) memory back"
                             : "No memory gain recorded")
                            .type(Face.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Space.m)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct Footer: View {
    let lifetime: Recap?
    let canErase: Bool
    @Binding var confirmingErase: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Rule()

            if let lifetime, !lifetime.isEmpty {
                Text(lifetimeSentence(lifetime))
                    .type(Face.caption)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: Space.l) {
                Text("Stored only on this Mac. No account. Nothing uploaded.")
                    .type(Face.caption)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                if canErase {
                    Button("Erase record…") { confirmingErase = true }
                        .buttonStyle(QuietStyle())
                        .fixedSize()
                        .accessibilityHint("Opens a confirmation before erasing all recorded actions and measurements.")
                }
            }
        }
    }

    private func lifetimeSentence(_ recap: Recap) -> String {
        let actions = recap.actionCount == 1 ? "1 action" : "\(recap.actionCount) actions"
        if recap.memoryFreedBytes > 0 {
            return "All time: \(Measure.memory(recap.memoryFreedBytes).inline) of memory back across \(actions)."
        }
        return "All time: \(actions) recorded."
    }
}
