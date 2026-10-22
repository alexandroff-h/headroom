import AppKit
import SwiftUI
import HeadroomCore

// MARK: - Buttons

/// The one filled control on a screen: the thing to do. Press is expressed as
/// a fill shift rather than a scale, so it lands identically whether it came
/// from the pointer or from the space bar on a focused button.
struct ActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(Face.row)
            .foregroundStyle(Ink.onAccent)
            .padding(.horizontal, Space.m)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Ink.accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(.black.opacity(configuration.isPressed ? 0.18 : (hovered ? 0.08 : 0)))
                    }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .pressable(configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

/// Everything else you can press. No fill at rest — on one material, a border
/// is enough to say "this is a control".
struct QuietStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .type(Face.row)
            .foregroundStyle(destructive ? Ink.critical : Ink.primary)
            .padding(.horizontal, Space.m)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Ink.wash(scheme, configuration.isPressed ? Ink.Wash.pressed : (hovered ? Ink.Wash.hover : 0)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Ink.ruleStrong, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .pressable(configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

/// A whole row that can be pressed. The fill bleeds outside the content rail so
/// the text still starts on it.
struct RowStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var selected = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let alpha = configuration.isPressed
            ? Ink.Wash.pressed
            : (selected ? Ink.Wash.selected : (hovered ? Ink.Wash.hover : 0))
        return configuration.label
            .padding(.horizontal, Metrics.rowBleed)
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(Ink.wash(scheme, alpha))
            }
            .padding(.horizontal, -Metrics.rowBleed)
            .contentShape(Rectangle())
            .pressable(configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

// MARK: - App icon

/// Icons come from the bundle on disk, and the list redraws every two seconds,
/// so both halves of the cost are cached: the filesystem lookup, and the
/// rasterisation.
///
/// The second one is the expensive half. `NSWorkspace.icon(forFile:)` hands
/// back a multi-representation image built around a 1024pt master; asking
/// SwiftUI to resample that down to 26pt with high interpolation, forty times
/// over, every two seconds, cost more processor time than every measurement in
/// the app put together. Drawing each icon once into an image at its final size
/// lets AppKit pick the representation that was already the right size.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var images: [Key: NSImage] = [:]

    private struct Key: Hashable {
        let path: String
        let size: CGFloat
    }

    func icon(forBundle path: String, size: CGFloat) -> NSImage? {
        let key = Key(path: path, size: size)
        if let cached = images[key] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: path)
        let sized = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        images[key] = sized
        return sized
    }
}

/// An app's face. When there is no bundle to take an icon from — a daemon, a
/// command-line tool — a glyph says which of the three kinds it is rather than
/// pretending there was an icon.
struct AppIcon: View {
    @Environment(\.colorScheme) private var scheme
    let app: RunningApp
    var size: CGFloat = Metrics.iconSize

    var body: some View {
        Group {
            if let path = app.bundlePath, let image = IconCache.shared.icon(forBundle: path, size: size) {
                Image(nsImage: image)
                    .frame(width: size, height: size)
                    // https://craft.gustavofior.com/image-outlines
                    // macOS icons are drawn to the squircle ratio, so the
                    // outline follows the same curve the artwork already has.
                    .imageOutline(radius: size * Radius.iconRatio, scheme: scheme)
            } else {
                RoundedRectangle(cornerRadius: Radius.icon, style: .continuous)
                    .strokeBorder(Ink.rule, lineWidth: 1)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: app.kind.symbol)
                            .font(.system(size: size * 0.44, weight: .regular))
                            .foregroundStyle(Ink.tertiary)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

extension AppKind {
    var symbol: String {
        switch self {
        case .app: "app"
        case .background: "arrow.triangle.2.circlepath"
        case .system: "apple.logo"
        case .unidentified: "questionmark"
        }
    }

    /// Shown beside the name when it is not simply an app you opened.
    var label: String? {
        switch self {
        case .app: nil
        case .background: "Background"
        case .system: "macOS"
        case .unidentified: "Unidentified"
        }
    }
}

// MARK: - Readings

/// A measured figure. The number is tabular so a column of them does not jitter
/// as digits change, and the unit sits in its own lane so `956 MB` becoming
/// `1 GB` does not reflow the row.
struct Reading: View {
    let measure: Measure
    var style: TypeStyle = Face.reading
    var unitStyle: TypeStyle = Face.caption
    var emphasis: Color = Ink.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(measure.integer + measure.fraction)
                .type(style)
                .monospacedDigit()
                .foregroundStyle(measure.isMeasured ? emphasis : Ink.tertiary)
            if !measure.unit.isEmpty {
                Text(measure.unit)
                    .type(unitStyle)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(measure.spoken)
    }
}

/// A short quiet label above a reading. Sentence case: the uppercase
/// wide-tracked version of this was retired.
struct MicroLabel: View {
    let text: String
    var color: Color = Ink.tertiary

    init(_ text: String, color: Color = Ink.tertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .type(Face.micro)
            .foregroundStyle(color)
    }
}

/// A section heading on the one surface: a strong label, a hairline under it,
/// and an optional figure on the right.
struct SectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .type(Face.section)
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: Space.m)
                trailing
            }
            Rule()
        }
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}
