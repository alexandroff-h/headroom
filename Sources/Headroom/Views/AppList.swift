import AppKit
import SwiftUI
import HeadroomCore

/// "Here is what you can kill", and on any row, "what IS this thing".
///
/// The list is of apps, not processes. A cryptic executable name is never the
/// title of a row: it appears inside, under the app it belongs to, where it is
/// an explanation rather than a riddle.
struct AppList: View {
    @Bindable var model: AppModel
    var query = ""
    @State private var showSystem = false

    private var matching: [RunningApp] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return model.apps }
        return model.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(term) || app.explanation.localizedCaseInsensitiveContains(term)
                || app.processes.contains { $0.name.localizedCaseInsensitiveContains(term) }
        }
    }
    private var yours: [RunningApp] { matching.filter { $0.kind != .system } }
    private var system: [RunningApp] { matching.filter { $0.kind == .system } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: query.isEmpty ? "Your apps" : "Search results") {
                HStack(spacing: Space.m) {
                    MicroLabel("Memory").frame(width: 84, alignment: .trailing)
                    MicroLabel("CPU").frame(width: 56, alignment: .trailing)
                }
            }
            if matching.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("No matching apps or processes.").type(Face.section).foregroundStyle(Ink.primary)
                    Text("Try an app name, or a process such as node or helper.").type(Face.body).foregroundStyle(Ink.secondary)
                }.padding(.vertical, Space.xxl)
            }

            ForEach(yours) { app in
                AppRow(app: app, model: model)
                Rule()
            }

            if query.isEmpty {
                SystemFold(apps: system, expanded: $showSystem, model: model)
            } else {
                ForEach(system) { app in
                    AppRow(app: app, model: model)
                    Rule()
                }
            }

            Text("Processor use is counted per core, so an app that is using more than one at a time goes over 100%. Memory is what every process in the app holds, added up.")
                .type(Face.caption)
                .foregroundStyle(Ink.tertiary)
                .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.m)
        }
        .onDisappear { model.pointerInList = false; model.focusedAppID = nil }
        .onContinuousHover { phase in
            // Freeze the order while the pointer is in here. A row that moves
            // out from under the cursor cannot be clicked.
            //
            // The guard matters: continuous hover fires on every mouse-moved
            // event, and writing the same value to an observed property still
            // invalidates everything that reads it.
            let inside: Bool
            switch phase {
            case .active: inside = true
            case .ended: inside = false
            }
            if model.pointerInList != inside { model.pointerInList = inside }
        }
    }

    private var summary: String {
        let processes = model.apps.reduce(0) { $0 + $1.processCount }
        return "\(yours.count) apps · \(processes) processes"
    }
}

// MARK: - A row, and what is inside it

struct AppRow: View {
    let app: RunningApp
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var expanded: Bool { model.expandedAppID == app.id }
    private var quitting: Bool { model.quittingIDs.contains(app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let pointer = NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown
                withAnimation(pointer && !reduceMotion ? Motion.reveal : nil) {
                    model.expandedAppID = expanded ? nil : app.id
                }
            } label: {
                header
            }
            .buttonStyle(RowStyle(selected: expanded))
            .focused($focused)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Collapse" : "Expand to see what this is")

            if expanded {
                Detail(app: app, model: model)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(quitting ? 0.45 : 1)
        .onChange(of: focused) { _, value in
            if value { model.focusedAppID = app.id }
            else if model.focusedAppID == app.id { model.focusedAppID = nil }
        }
        .onDisappear { if model.focusedAppID == app.id { model.focusedAppID = nil } }
        .animation(reduceMotion ? nil : Motion.leave, value: quitting)
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)

            AppIcon(app: app)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .type(Face.row)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .help(app.name)
                Text(subtitle)
                    .type(Face.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.l)

            Reading(measure: Measure.memory(app.memoryBytes))
                .frame(width: 84, alignment: .trailing)
            Reading(measure: Measure.percent(app.cpuPercent, digits: 0))
                .frame(width: 56, alignment: .trailing)
        }
        .frame(height: Metrics.row)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let label = app.kind.label { parts.append(label) }
        if app.processCount > 1 { parts.append("\(app.processCount) processes") }
        if let origin = app.origin, parts.isEmpty { parts.append(origin) }
        return parts.isEmpty ? (app.origin ?? "One process") : parts.joined(separator: " · ")
    }
}

/// "What IS this thing." Everything a person needs to decide whether closing it
/// is safe: what it is, where it came from, and what its processes are doing.
private struct Detail: View {
    let app: RunningApp
    @Bindable var model: AppModel

    /// Four identical rows called "Helium Helper (Renderer)" answer nobody's
    /// question. Processes that share a name are one line with a count.
    private struct Family: Identifiable {
        var id: String { name }
        let name: String
        var count: Int
        var memoryBytes: UInt64
        var cpuPercent: Double
    }

    private var families: [Family] {
        var order: [String] = []
        var byName: [String: Family] = [:]
        for process in app.processes {
            if var existing = byName[process.name] {
                existing.count += 1
                existing.memoryBytes &+= process.memoryBytes
                existing.cpuPercent += process.cpuPercent
                byName[process.name] = existing
            } else {
                order.append(process.name)
                byName[process.name] = Family(name: process.name, count: 1, memoryBytes: process.memoryBytes, cpuPercent: process.cpuPercent)
            }
        }
        return order.compactMap { byName[$0] }.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    private var visible: [Family] { Array(families.prefix(5)) }
    private var hidden: Int { families.count - visible.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(app.explanation)
                .type(Face.body)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let origin = app.origin {
                Field(label: "Where it came from", value: origin)
            }
            if let identifier = app.bundleIdentifier {
                Field(label: "Identifier", value: identifier)
            }

            if app.processCount > 1 || visible.first?.name != app.name {
                VStack(alignment: .leading, spacing: Space.s) {
                    MicroLabel(app.processCount == 1 ? "Its process" : "What it is running")
                    ForEach(visible) { family in
                        HStack(spacing: Space.s) {
                            Text(family.name)
                                .type(Face.caption)
                                .foregroundStyle(Ink.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if family.count > 1 {
                                Text("×\(family.count)")
                                    .type(Face.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Ink.tertiary)
                            }
                            Spacer(minLength: Space.m)
                            Reading(measure: Measure.memory(family.memoryBytes), style: Face.caption)
                                .frame(width: 72, alignment: .trailing)
                            Reading(measure: Measure.percent(family.cpuPercent, digits: 0), style: Face.caption)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    if hidden > 0 {
                        Text(hidden == 1 ? "and one smaller kind" : "and \(hidden) smaller kinds")
                            .type(Face.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .frame(maxWidth: Metrics.proseMeasure + 60, alignment: .leading)
            }

            actions
        }
        .padding(.leading, 10 + Space.m + Metrics.iconSize + Space.m)
        .padding(.trailing, Space.m)
        .padding(.bottom, Space.l)
        .padding(.top, Space.xs)
    }

    @ViewBuilder private var actions: some View {
        if app.kind == .system {
            Text("Headroom will not offer to quit this. macOS restarts it immediately, and stopping it by hand can take parts of the system down with it.")
                .type(Face.caption)
                .foregroundStyle(Ink.tertiary)
                .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else if app.canQuit {
            HStack(spacing: Space.s) {
                QuitButton(app: app, primary: true, label: "Quit \(app.name)", model: model)
                Button("Force quit") { model.confirmingForceQuit = app }
                    .buttonStyle(QuietStyle(destructive: true))
                    .disabled(model.isMeasuringAction)
                if model.quittingIDs.contains(app.id) {
                    Text("Asked. Waiting for it to finish saving.")
                        .type(Face.caption)
                        .foregroundStyle(Ink.tertiary)
                }
            }
        } else {
            Text("No app is registered for these processes, so there is nothing for Headroom to ask. Whatever started them has to stop them.")
                .type(Face.caption)
                .foregroundStyle(Ink.tertiary)
                .frame(maxWidth: Metrics.proseMeasure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Field: View {
        let label: String
        let value: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(label)
                    .type(Face.caption)
                    .foregroundStyle(Ink.tertiary)
                    .frame(width: 128, alignment: .leading)
                Text(value)
                    .type(Face.caption)
                    .foregroundStyle(Ink.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - The part of the list that is not yours to manage

/// macOS processes are collapsed behind one line. They are in the list because
/// hiding them would make the totals lie, and folded because quitting them is
/// not a thing a person should be invited to do.
private struct SystemFold: View {
    let apps: [RunningApp]
    @Binding var expanded: Bool
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Ink.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 10)
                        Text("and \(apps.count) parts of macOS")
                            .type(Face.caption)
                            .foregroundStyle(Ink.tertiary)
                        Spacer(minLength: Space.l)
                        Reading(measure: Measure.memory(total), style: Face.caption)
                            .frame(width: 84, alignment: .trailing)
                        Reading(measure: Measure.percent(cpu, digits: 0), style: Face.caption)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .frame(height: 34)
                }
                .buttonStyle(RowStyle())

                if expanded {
                    Rule()
                    ForEach(apps) { app in
                        AppRow(app: app, model: model)
                        Rule()
                    }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.reveal, value: expanded)
        }
    }

    private var total: UInt64 { apps.reduce(UInt64(0)) { $0 &+ $1.memoryBytes } }
    private var cpu: Double { apps.reduce(0.0) { $0 + $1.cpuPercent } }
}
