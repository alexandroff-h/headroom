import AppKit
import SwiftUI

// ONE MATERIAL. The window background is the only surface in this app.
// Nothing floats on it, nothing is darker than it, nothing has a shadow.
// Space is divided by hairlines and by emptiness, never by a card.
//
// The previous version of Headroom put a white settings pane beside a dark
// chart box, and two materials in one window is what makes a window read as a
// sheet. Every reference on the board commits to one: AccessGrid divides plain
// white with dashed rules, the dark card grid uses no borders at all.
//
// Acceptance test: no view file outside Design/ contains a literal colour, and
// no view file anywhere calls `.shadow(`.

extension Color {
    /// Resolves per appearance, so one token serves light and dark.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(srgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(srgb value: UInt32) {
        self.init(
            srgbRed: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255,
            alpha: 1
        )
    }
}

/// Every colour in Headroom. Each contrast figure below was measured against
/// its own surface, not estimated.
enum Ink {
    private static let surfaceLight: UInt32 = 0xFBFBF9
    private static let surfaceDark: UInt32 = 0x141417

    /// The one material.
    static let surface = Color(light: surfaceLight, dark: surfaceDark)

    /// The window's own background, so a live resize never flashes a tone the
    /// drawn surface does not use.
    static let surfaceNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(srgb: isDark ? surfaceDark : surfaceLight)
    }

    /// 17.3:1 light · 16.4:1 dark.
    static let primary = Color(light: 0x17171A, dark: 0xF2F2EF)
    /// 7.1:1 light · 7.4:1 dark.
    static let secondary = Color(light: 0x55555E, dark: 0xA3A3AC)
    /// 4.9:1 light · 5.4:1 dark. The floor: nothing in the app is quieter.
    static let tertiary = Color(light: 0x6E6E78, dark: 0x8A8A94)

    /// Divides space. Non-text, so it is allowed to recede.
    static let rule = Color(light: 0xE4E4E0, dark: 0x28282E)
    static let ruleStrong = Color(light: 0xD6D6D2, dark: 0x34343B)

    /// The accent appears once per screen: on the thing to do. It never touches
    /// a figure, a heading, or a reading. 5.9:1 against its own white label.
    static let accent = Color(light: 0x2158E0, dark: 0x2158E0)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Accent as text, for the one or two places a fill would be too loud.
    static let accentInk = Color(light: 0x1B4FD8, dark: 0x8CB0FF)

    /// Severity. Nominal has no colour at all — the sentence carries it.
    static let caution = Color(light: 0x8A5200, dark: 0xE7AE5E)
    static let critical = Color(light: 0xA41F26, dark: 0xF2918F)
    /// Reserved for a measured gain. This is the only green in the app, and it
    /// only ever appears after the reader has done something.
    static let gain = Color(light: 0x15704A, dark: 0x6CC79B)

    /// Hover and press are alpha over the one surface, never a second hex.
    static func wash(_ scheme: ColorScheme, _ alpha: Double) -> Color {
        scheme == .dark ? Color.white.opacity(alpha) : Color.black.opacity(alpha)
    }

    enum Wash {
        static let hover = 0.045
        static let pressed = 0.085
        static let selected = 0.06
    }
}

/// Six values. Every gap and pad comes from here.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 36
}

enum Radius {
    static let control: CGFloat = 7
    /// The ratio macOS draws app-icon squircles to.
    static let iconRatio: CGFloat = 0.2237
    static let row: CGFloat = 9
    static let icon: CGFloat = 6
}

/// The layout constants, named rather than scattered.
enum Metrics {
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 780
    static let minimumWidth: CGFloat = 680
    static let minimumHeight: CGFloat = 560

    /// One content rail, top to bottom. Every heading, row name and figure
    /// starts or ends on it.
    static let gutter: CGFloat = 36
    /// Row fills bleed outside the rail so the text still starts on it.
    static let rowBleed: CGFloat = 10

    static let iconSize: CGFloat = 32
    static let row: CGFloat = 58
    static let suggestionRow: CGFloat = 64

    /// The explanation column. Prose wider than this stops being scannable.
    static let proseMeasure: CGFloat = 480
    static let verdictMeasure: CGFloat = 560
}

// MARK: - Type

struct TypeStyle {
    let font: Font
    var tracking: CGFloat = 0
    var lineSpacing: CGFloat = 0
    var uppercase = false
}

extension View {
    func type(_ style: TypeStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

/// Nine roles. Hierarchy is carried by size and weight, because there is only
/// one surface to carry it on.
enum Face {
    // The system face. SF is what a Mac utility is set in, and every reading in
    // this app is a number the system itself reported.
    static let verdict = TypeStyle(font: .system(size: 27, weight: .semibold), tracking: -0.5)
    static let figure = TypeStyle(font: .system(size: 30, weight: .medium), tracking: -0.4)
    static let section = TypeStyle(font: .system(size: 13, weight: .semibold), tracking: -0.05)
    static let row = TypeStyle(font: .system(size: 13, weight: .medium), tracking: -0.05)
    static let reading = TypeStyle(font: .system(size: 13, weight: .medium))
    static let body = TypeStyle(font: .system(size: 12), lineSpacing: 2.5)
    static let caption = TypeStyle(font: .system(size: 11))
    /// A quiet label above a reading. Sentence case, no letterspacing.
    /// Uppercase wide-tracked labels above every section were the loudest tell
    /// on this screen and they are not coming back.
    static let micro = TypeStyle(font: .system(size: 11))
    static let brand = TypeStyle(font: .system(size: 15, weight: .semibold), tracking: -0.3)
}

// MARK: - Dividers

/// One point on every display, heavier under Increase Contrast rather than
/// thinner. Nothing in the app strokes below 1pt.
struct Rule: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var strong = false

    var body: some View {
        Rectangle()
            .fill(strong ? Ink.ruleStrong : Ink.rule)
            .frame(height: contrast == .increased ? 1.5 : 1)
            .accessibilityHidden(true)
    }
}

/// The dashed rule AccessGrid uses to divide a plain surface. It says "these
/// are separate regions" without drawing a box around either of them.
struct DashedRule: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(
                        contrast == .increased ? Ink.ruleStrong : Ink.rule,
                        style: StrokeStyle(lineWidth: contrast == .increased ? 1.5 : 1, dash: [3, 3])
                    )
                }
            }
            .accessibilityHidden(true)
    }
}
