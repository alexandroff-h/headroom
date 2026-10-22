import SwiftUI
import HeadroomCore

/// Who is using this reading, as a share.
///
/// **Form.** Part-to-whole, but the job is not "tell eight series apart" — it is
/// "which one of these should I close". That is the emphasis case: the leader
/// carries the one accent, everything else is a neutral, and the segments read
/// apart because of the gap between them rather than because of a hue each.
/// A categorical ramp here would be a rainbow in an app that has one accent,
/// and colouring segments by rank would repaint every app each time the order
/// changed, which is the thing a categorical palette may never do.
///
/// **Honesty.** Resident memory counts pages shared between apps, and processor
/// use is counted per core, so neither column sums to the system figure above
/// it. The bar is therefore a share of *what the apps are using between them*,
/// never a fill level against capacity, and the caption says which.
struct ShareBar: View {
    struct Slice: Identifiable, Equatable {
        let id: String
        let name: String
        let value: Double
    }

    let slices: [Slice]
    /// How each slice's value reads in a tooltip.
    let format: (Double) -> String
    @Binding var highlighted: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 7
    /// A 2pt surface gap is what separates touching segments. One consistent
    /// width across the whole stack, never a stroke drawn around each piece.
    private let gap: CGFloat = 2

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, .leastNonzeroMagnitude) }

    var body: some View {
        GeometryReader { proxy in
            let usable = max(0, proxy.size.width - gap * CGFloat(max(0, slices.count - 1)))
            HStack(spacing: gap) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    let share = slice.value / total
                    Rectangle()
                        .fill(fill(index: index, slice: slice))
                        .frame(width: max(1, usable * share))
                        .onHover { inside in
                            highlighted = inside ? slice.id : (highlighted == slice.id ? nil : highlighted)
                        }
                }
            }
            // The outer ends are the only rounded ones: a stack grows from a
            // baseline, so its interior joints stay square.
            .clipShape(Capsule(style: .continuous))
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func fill(index: Int, slice: Slice) -> Color {
        if let highlighted {
            return highlighted == slice.id ? Ink.accent : Ink.rule
        }
        // Emphasis: the biggest contributor is the one you would act on.
        return index == 0 ? Ink.accent : Ink.rule
    }

    private func percent(_ share: Double) -> String {
        Measure.percent(share * 100, digits: 0).inline
    }

    private var spoken: String {
        slices.prefix(3)
            .map { "\($0.name) \(percent($0.value / total))" }
            .joined(separator: ", ")
    }
}

/// A reading, its share bar, and the one line that says who is on top.
struct ReadingBreakdown: View {
    let apps: [RunningApp]
    /// Pulls the figure this reading is about out of an app.
    let amount: (RunningApp) -> Double
    let format: (Double) -> String
    /// "of what apps are using" wording differs per reading.
    let noun: String

    @State private var highlighted: String?

    var body: some View {
        // Built once per render. This used to be a computed property read five
        // times in the same pass, so every repaint map-filter-sorted three
        // hundred apps five times over, twice on screen. That alone was most
        // of the app's own processor use.
        let model = Model(apps: apps, amount: amount)
        VStack(alignment: .leading, spacing: 6) {
            if model.slices.isEmpty {
                Rectangle().fill(Ink.rule).frame(height: 7).clipShape(Capsule())
            } else {
                ShareBar(slices: model.slices, format: format, highlighted: $highlighted)
            }

            Group {
                if let shown = model.shown(highlighted), model.total > 0 {
                    Text("\(shown.name) \(Measure.percent(shown.value / model.total * 100, digits: 0).inline) \(noun)")
                } else {
                    Text("waiting for a reading")
                }
            }
            .type(Face.caption)
            .foregroundStyle(Ink.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .animation(nil, value: highlighted)
        }
    }

    private struct Model {
        let slices: [ShareBar.Slice]
        let total: Double

        init(apps: [RunningApp], amount: (RunningApp) -> Double) {
            var ranked: [ShareBar.Slice] = []
            ranked.reserveCapacity(apps.count)
            for app in apps {
                let value = amount(app)
                if value > 0 { ranked.append(.init(id: app.id, name: app.name, value: value)) }
            }
            ranked.sort { $0.value > $1.value }
            guard !ranked.isEmpty else {
                slices = []
                total = 0
                return
            }
            // Eight is the ceiling for pieces anyone can tell apart; the tail
            // becomes one segment rather than a row of unhittable slivers.
            let head = Array(ranked.prefix(8))
            let tail = ranked.dropFirst(8).reduce(0) { $0 + $1.value }
            slices = tail > 0
                ? head + [.init(id: "other", name: "Everything else", value: tail)]
                : head
            total = slices.reduce(0) { $0 + $1.value }
        }

        var leader: ShareBar.Slice? {
            guard let first = slices.first, first.id != "other" else { return nil }
            return first
        }

        func shown(_ highlighted: String?) -> ShareBar.Slice? {
            guard let highlighted else { return leader }
            return slices.first { $0.id == highlighted } ?? leader
        }
    }
}
