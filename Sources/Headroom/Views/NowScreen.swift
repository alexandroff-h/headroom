import SwiftUI
import HeadroomCore

struct NowScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        Page {
            Verdict(diagnosis: model.diagnosis, snapshot: model.snapshot, apps: model.apps)

            if let payoff = model.payoff {
                PayoffLine(payoff: payoff) { model.dismissPayoff() }
                    .padding(.top, Space.xl)
            }

            Suggestions(model: model)
                .padding(.top, Space.xxl)

            RunningPreview(model: model)
                .padding(.top, Space.xxl)

            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("On your Mac. For your Mac.").type(Face.caption)
                Spacer()
                Text("No accounts. No uploads.").type(Face.caption)
            }
            .foregroundStyle(Ink.tertiary)
            .padding(.top, Space.l)

            if !model.warnings.isEmpty {
                Unavailable(warnings: model.warnings).padding(.top, Space.xl)
            }
        }
    }
}

/// The verdict block.
///
/// Composed, not decorated. The readings are three plain stacks on one
/// baseline: no vertical rules boxing them into three equal cards, and no
/// 32-bar tick strip under each one. A row of little bars that restates the
/// number above it is instrument cosplay, and the board is explicit that this
/// app is not a dashboard.
private struct Verdict: View {
    let diagnosis: Diagnosis?
    let snapshot: SystemSnapshot?
    let apps: [RunningApp]

    /// macOS is in the list so the totals do not lie, but it is not something
    /// the reader can act on, so it does not get a segment of its own.
    private var yours: [RunningApp] { apps.filter { $0.kind != .system } }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(diagnosis?.title ?? "Reading the room.")
                .type(Face.verdict)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(diagnosis?.explanation ?? "Your first readings will be here in a moment.")
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: 560, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)

            HStack(alignment: .top, spacing: Space.l) {
                reading("Processor", value: .percent(snapshot?.cpuPercent, digits: 0), cause: .cpu) {
                    ReadingBreakdown(
                        apps: yours,
                        amount: { $0.cpuPercent },
                        format: { Measure.percent($0, digits: 0).inline },
                        noun: "of the work"
                    )
                }
                reading("Memory", value: Measure.memory(snapshot?.memoryUsedBytes), cause: .memory) {
                    ReadingBreakdown(
                        apps: yours,
                        amount: { Double($0.memoryBytes) },
                        format: { Measure.memory(UInt64($0)).inline },
                        noun: "of what apps hold"
                    )
                }
                word(
                    "Pressure",
                    value: (snapshot?.memoryPressure ?? .unknown).title,
                    detail: pressureDetail
                )
            }
            .padding(.top, Space.l)

            DashedRule().padding(.top, Space.l)
        }
        .padding(.top, Space.xl)
    }

    /// The app is called Headroom and never showed any. "19.8 of 24 GB in use"
    /// is the inverse of the thing the reader came for.
    private var headroomBytes: UInt64? {
        guard let snapshot, let used = snapshot.memoryUsedBytes else { return nil }
        return snapshot.memoryTotalBytes > used ? snapshot.memoryTotalBytes - used : 0
    }

    private func reading<Below: View>(
        _ label: String,
        value: Measure,
        cause: DiagnosisCause,
        @ViewBuilder below: () -> Below
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(label)
            // No numeric morph here, deliberately. `.numericText()` on these
            // two figures measured at ~8% of a core: it re-morphs 30pt glyphs
            // on a 120Hz display every two seconds, which is five times this
            // whole app's processor budget. A reading that changes this often
            // should land instantly anyway; the Recap screen keeps the morph
            // because its figures change once in a while.
            Reading(measure: value, style: Face.figure, unitStyle: Face.body, emphasis: emphasis(for: cause))
                .padding(.top, 6)
            below()
                .padding(.top, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func word(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(label)
            Text(value)
                .type(Face.figure)
                .foregroundStyle(emphasis(for: .memory))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)
            Text(detail)
                .type(Face.caption).foregroundStyle(Ink.tertiary)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emphasis(for cause: DiagnosisCause) -> Color {
        guard let diagnosis, diagnosis.cause == cause else { return Ink.primary }
        switch diagnosis.severity {
        case .critical: return Ink.critical
        case .attention: return Ink.caution
        case .healthy: return Ink.primary
        }
    }

    private var pressureDetail: String {
        switch snapshot?.memoryPressure ?? .unknown {
        case .normal: "room to work"
        case .warning: "memory under strain"
        case .critical: "memory under heavy strain"
        case .unknown: "not reported by macOS"
        }
    }
}

extension MemoryPressure {
    var title: String {
        switch self { case .normal: "Normal"; case .warning: "Elevated"; case .critical: "Critical"; case .unknown: "Unknown" }
    }
}

// MARK: - What the action actually bought you

/// The payoff. This is the only place in Headroom that claims an improvement,
/// and the claim is always a measurement taken after the fact.
private struct PayoffLine: View {
    let payoff: Payoff
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far through the settling window the measurement is, 0 to 1.
    private var settled: Double {
        guard Impact.settleSeconds > 0 else { return 1 }
        let left = Double(payoff.remaining)
        return min(1, max(0, 1 - left / Impact.settleSeconds))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 14)
                .symbolEffect(.pulse, isActive: payoff.isMeasuring && !reduceMotion)

            sentence
                .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.m)

            if payoff.isMeasuring {
                Text("\(payoff.remaining)s")
                    .type(Face.caption)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Motion.reading, value: payoff.remaining)
                    .foregroundStyle(Ink.tertiary)
            } else {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Ink.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, Space.m)
        .overlay(alignment: .top) { Rule() }
        // The measurement takes twelve seconds whether or not anyone says so.
        // A bottom rule that fills over exactly that window turns the wait
        // into something the reader can watch finish, and it doubles as the
        // divider the block needs anyway.
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rule()
                    if payoff.isMeasuring {
                        Rectangle()
                            .fill(Ink.accentInk)
                            .frame(width: proxy.size.width * settled, height: 1.5)
                            .animation(reduceMotion ? nil : .linear(duration: 1), value: settled)
                    }
                }
                .frame(height: 2, alignment: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 2)
        }
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: Motion.rise)),
                    removal: .opacity
                )
        )
        .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.arrive, value: payoff)
    }

    @ViewBuilder private var sentence: some View {
        switch payoff.verdict {
        case .measuring:
            Text(payoff.statusText)
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
        case .freed:
            (
                Text(gainPhrase).foregroundStyle(Ink.gain).fontWeight(.semibold)
                    + Text("  \(payoff.appName) quit.").foregroundStyle(Ink.secondary)
            )
            .type(Face.body)
        case .noChange:
            Text("\(payoff.appName) quit. No measurable improvement in the readings.")
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
        case .offset:
            Text("\(payoff.appName) quit. Overall usage rose during the measurement. No improvement recorded.")
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
        case .unknown:
            Text(payoff.statusText)
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
        }
    }

    private var gainPhrase: String {
        var parts: [String] = []
        if let memory = payoff.memoryDeltaBytes, memory >= Impact.memoryNoiseFloor {
            parts.append("\(Measure.memory(UInt64(memory)).inline) of memory back.")
        }
        if let cpu = payoff.cpuDelta, cpu >= Impact.cpuNoiseFloor {
            parts.append("\(Measure.percent(cpu, digits: 0).inline) of the processor back.")
        }
        return parts.isEmpty ? "Measurably better." : parts.joined(separator: " ")
    }

    private var symbol: String {
        switch payoff.verdict {
        case .measuring: "circle.dotted"
        case .freed: "checkmark.circle.fill"
        case .noChange, .offset: "equal.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var tint: Color {
        switch payoff.verdict {
        case .freed: Ink.gain
        case .measuring: Ink.accentInk
        default: Ink.tertiary
        }
    }
}


private struct Suggestions: View {
    @Bindable var model: AppModel
    @State private var held: [Suggestion]?
    @State private var hovered = false
    @FocusState private var focused: Bool
    @State private var showsMethod = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var suggestions: [Suggestion] { held ?? model.suggestions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.snapshot == nil ? "Looking at what is running" : suggestions.isEmpty ? "Nothing worth closing" : "Three things you could do")
                    .type(Face.section).foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.snapshot != nil, !suggestions.isEmpty {
                    Text("By size and activity")
                        .type(Face.caption).foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.bottom, Space.l)

            if model.snapshot == nil {
                HStack(spacing: Space.m) {
                    ProgressView().controlSize(.small)
                    Text("Checking what’s running and what it’s using.").type(Face.body).foregroundStyle(Ink.secondary)
                }.frame(minHeight: 76, alignment: .leading)
            } else if suggestions.isEmpty {
                HStack(alignment: .top, spacing: Space.l) {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .light)).foregroundStyle(Ink.secondary).frame(width: 32)
                    Text("Nothing stands out as worth the interruption. You can still explore every app and see what it is doing.")
                        .type(Face.body).foregroundStyle(Ink.secondary)
                        .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Space.l)
            } else {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Rule()
                    SuggestionRow(suggestion: suggestion, primary: index == 0, model: model)
                        .focused($focused)
                        .transition(.opacity)
                }
                Rule()
                HStack(spacing: 5) {
                    Text("Memory held now. Savings measured after you close.")
                        .type(Face.caption).foregroundStyle(Ink.tertiary)
                    Button { showsMethod.toggle() } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.tertiary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How improvement is measured")
                    .popover(isPresented: $showsMethod, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Measured, never promised.").type(Face.section).foregroundStyle(Ink.primary)
                            Text("Apps share memory, so their footprint isn't the amount quitting will return. Headroom confirms the app has closed, lets your Mac settle, and compares fresh readings. Small differences are treated as noise.")
                                .type(Face.body).foregroundStyle(Ink.secondary)
                        }
                        .padding(Space.xl).frame(width: 320).background(Ink.surface)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Space.s)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: suggestions.map(\.id))
        .onHover { inside in
            hovered = inside
            updateHold()
        }
        .onChange(of: focused) { _, _ in updateHold() }
    }

    private func updateHold() {
        if hovered || focused {
            if held == nil { held = model.suggestions }
        } else { held = nil }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let primary: Bool
    @Bindable var model: AppModel
    private var app: RunningApp? { model.app(id: suggestion.id) }
    private var quitting: Bool { model.quittingIDs.contains(suggestion.id) }

    var body: some View {
        HStack(spacing: Space.l) {
            if let app { AppIcon(app: app) }
            VStack(alignment: .leading, spacing: 3) {
                Text(app?.name ?? suggestion.headline)
                    .type(Face.row).foregroundStyle(Ink.primary).lineLimit(1)
                Text(suggestion.reason)
                    .type(Face.caption).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.l)
            VStack(alignment: .trailing, spacing: 2) {
                Reading(measure: Measure.memory(app?.memoryBytes ?? suggestion.footprintBytes))
                Text("holding").type(Face.caption).foregroundStyle(Ink.tertiary)
            }
            .frame(minWidth: 72, alignment: .trailing)
            QuitButton(app: app, primary: primary, model: model)
        .padding(.vertical, Space.l)
        .accessibilityElement(children: .contain)
    }

}
}

// MARK: - When a reading is missing

/// The bottom half used to be one call-to-action row and then nothing. The
/// reader came to see what is on their Mac, so show them, and let the Apps tab
/// be the place they go for the rest rather than the only place there is one.
private struct RunningPreview: View {
    @Bindable var model: AppModel

    private var apps: [RunningApp] { Array(model.apps.filter { $0.kind != .system }.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Everything running")
                    .type(Face.section).foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.l)
                Button { model.screen = .apps } label: {
                    HStack(spacing: 5) {
                        Text(summary).type(Face.caption)
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Ink.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("See every app and what it is")
            }
            .padding(.bottom, Space.s)

            ForEach(apps) { app in
                Rule()
                AppRow(app: app, model: model)
            }
            if !apps.isEmpty { Rule() }

            Text("Processor use is counted per core, so an app using more than one at a time goes over 100%.")
                .type(Face.caption).foregroundStyle(Ink.tertiary)
                .padding(.top, Space.m)
        }
        .onContinuousHover { phase in
            let inside: Bool
            switch phase {
            case .active: inside = true
            case .ended: inside = false
            }
            if model.pointerInList != inside { model.pointerInList = inside }
        }
    }

    private var summary: String {
        let total = model.apps.filter { $0.kind != .system }.count
        return total == 0 ? "All apps" : "All \(total) apps"
    }
}

private struct Unavailable: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Rule()
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.tertiary)
                    Text(warning)
                        .type(Face.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
        .padding(.top, Space.s)
    }
}
