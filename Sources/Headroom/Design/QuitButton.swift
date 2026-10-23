import SwiftUI
import HeadroomCore

/// The button carries the whole life of the action it starts.
///
/// Quitting is not one event. Headroom asks, the app decides when to go (it may
/// put up a save dialog), the system settles, and only then is there a number.
/// That is roughly fifteen seconds in which the old button sat there looking
/// exactly as it had before the click, while all the feedback happened in a
/// different part of the window.
///
/// So it has four states, and each one is the honest word for what is true:
/// **Quit app** → **Asked** (the request is out, the app has not gone yet) →
/// **Measuring**, with the accent sweeping the capsule over the settle window →
/// gone, because the row leaves and the payoff line has the number.
struct QuitButton: View {
    let app: RunningApp?
    var primary: Bool = false
    var label: String = "Quit app"
    @Bindable var model: AppModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var pressed = false

    private var asked: Bool { app.map { model.quittingIDs.contains($0.id) } ?? false }

    /// Only this app's own measurement drives this button.
    private var settling: Double? {
        guard let app, let payoff = model.payoff, payoff.isMeasuring, payoff.appName == app.name,
              Impact.settleSeconds > 0 else { return nil }
        return min(1, max(0, 1 - Double(payoff.remaining) / Impact.settleSeconds))
    }

    private var phase: Phase {
        if settling != nil { return .measuring }
        if asked { return .asked }
        return .ready
    }

    private enum Phase { case ready, asked, measuring }

    private var title: String {
        switch phase {
        case .ready: label
        case .asked: "Asked"
        case .measuring: "Measuring"
        }
    }

    private var filled: Bool { primary && phase == .ready }

    var body: some View {
        Button {
            if let app { model.quit(app) }
        } label: {
            Text(title)
                // The width is held across all three words so the row never
                // reflows mid-action. "Measuring" is the longest.
                .frame(minWidth: 74)
                .contentTransition(reduceMotion ? .identity : .opacity)
        }
        .buttonStyle(QuitButtonStyle(
            filled: filled,
            progress: settling,
            dimmed: phase == .asked,
            hovered: hovered,
            scheme: scheme
        ))
        .disabled(app == nil || phase != .ready || model.isMeasuringAction)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: phase)
        .accessibilityLabel(accessibilityText)
        .help(helpText)
    }

    private var accessibilityText: String {
        let name = app?.name ?? "this app"
        switch phase {
        case .ready: return "Quit \(name)"
        case .asked: return "\(name) has been asked to quit"
        case .measuring: return "Measuring what quitting \(name) gave back"
        }
    }

    private var helpText: String {
        switch phase {
        case .ready:
            return model.isMeasuringAction
                ? "Finish measuring the last action before closing another app"
                : "Ask this app to quit, then measure the difference"
        case .asked: return "Waiting for the app to finish saving and close"
        case .measuring: return "Letting the Mac settle before taking a reading"
        }
    }
}

/// The material. On macOS 26 the system draws it: accent-tinted glass for the
/// one filled button, clear glass for the rest, both lit by the pointer that
/// is over them. Before 26 there is no glass to ask for, so the filled button
/// falls back to a gradient — lighter at the top, because light comes from
/// above — and the rest to a hairline border.
private struct QuitButtonStyle: ButtonStyle {
    let filled: Bool
    let progress: Double?
    let dimmed: Bool
    let hovered: Bool
    let scheme: ColorScheme

    /// macOS 26 rounds a control of this height to a capsule, and the tabs in
    /// the toolbar above are already capsules. Before 26 the house radius is
    /// the right answer, because every other control on screen uses it.
    private var glass: Bool { Liquid.isAvailable }
    private var radius: CGFloat { glass ? 16 : Radius.control }
    private var shape: AnyShape {
        glass ? AnyShape(Capsule()) : AnyShape(fallbackShape)
    }

    /// `strokeBorder` insets the line inward so a 1pt border never straddles
    /// the edge, and it needs the concrete shape — `AnyShape` erases down to
    /// `Shape`, which cannot inset. Only the fallback strokes anything.
    private var fallbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed

        configuration.label
            .type(Face.row)
            .foregroundStyle(filled ? Ink.onAccent : (dimmed ? Ink.tertiary : Ink.primary))
            // Optical padding: the label is the only thing in the box, so the
            // box is symmetric, but a pressed button loses a little air.
            .padding(.horizontal, glass ? Space.l : Space.m)
            .frame(height: 32)
            // Behind the label but in front of the glass, so the material
            // still reads through everything drawn here.
            .background {
                ZStack {
                    if !glass {
                        if filled {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        Ink.accent.lighter(by: hovered ? 0.11 : 0.07),
                                        Ink.accent,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            // Press darkens the whole face rather than moving
                            // it, so the label never drifts under the pointer.
                            shape.fill(.black.opacity(down ? 0.16 : 0))
                        } else {
                            shape.fill(Ink.wash(scheme, down ? Ink.Wash.pressed : (hovered ? Ink.Wash.hover : 0)))
                        }
                    }

                    // The settle window, swept across the face. This is the
                    // only progress in the app that is genuinely determinate:
                    // the wait is a fixed twelve seconds by design.
                    if let progress {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(Ink.accent.opacity(scheme == .dark ? 0.30 : 0.18))
                                .frame(width: proxy.size.width * progress)
                                .animation(.linear(duration: 1), value: progress)
                        }
                        // And a beam over it, because a fill creeping across
                        // twelve seconds cannot say "still working" on its own.
                        Beam()
                    }
                }
                .clipShape(shape)
            }
            .liquid(in: shape, tint: filled ? Ink.accent : nil)
            // The filled button only: see the note on litByPointer. The clear
            // one is already lit by the material it is made of.
            .litByPointer(radius: radius, enabled: filled)
            .overlay {
                // Glass draws its own edge and its own specular. Only the
                // fallback has to build one.
                if !glass {
                    if filled {
                        // Light from above: a bright top arc fading out by the
                        // midpoint, never a full outline.
                        fallbackShape.strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(down ? 0.12 : 0.34), location: 0),
                                    .init(color: .white.opacity(0), location: 0.55),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    } else {
                        fallbackShape.strokeBorder(dimmed ? Ink.rule : Ink.ruleStrong, lineWidth: 1)
                    }
                }
            }
            // Tinted with the fill's own hue, never black, and kept tight:
            // a wide soft coloured shadow stops reading as contact and starts
            // reading as a glow. Glass carries its own depth, so this is the
            // fallback's job only.
            .modifier(ContactShadow(
                active: filled && !glass,
                color: Ink.accent.opacity(down ? 0.08 : (hovered ? 0.22 : 0.15)),
                radius: down ? 2 : (hovered ? 6 : 4),
                offset: down ? 1 : (hovered ? 3 : 2)
            ))
            .pressable(down, scale: 0.975)
            .opacity(dimmed ? 0.75 : 1)
            // Hover is instant; only the press is animated.
            // https://craft.gustavofior.com/hover-restraint
            .animation(.easeOut(duration: 0.13), value: down)
    }
}

extension Color {
    /// Mixes toward white, for the top of a fill where the light lands.
    func lighter(by amount: Double) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(nsColor: base.blended(withFraction: amount, of: .white) ?? base)
    }
}

/// Only the filled fallback is lifted off the page, so only it pays for an
/// offscreen pass.
private struct ContactShadow: ViewModifier {
    let active: Bool
    let color: Color
    let radius: CGFloat
    let offset: CGFloat

    func body(content: Content) -> some View {
        if active {
            content.compositingGroup().shadow(color: color, radius: radius, y: offset)
        } else {
            content
        }
    }
}
