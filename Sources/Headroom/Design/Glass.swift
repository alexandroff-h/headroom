import SwiftUI

// MARK: - The material
//
// Liquid Glass is gated three times, and only two of them are in this file.
//
// At compile time, because `glassEffect` exists only in the macOS 26 SDK and
// Headroom still builds with the Command Line Tools, whose SDK is older.
// build-app.sh defines LIQUID_GLASS when the SDK it found can see the API.
//
// At runtime, because the binary deploys back to macOS 14. Below 26 every call
// site falls back to what it had before: a gradient on the one filled button,
// a hairline border on everything else.
//
// The third gate is the one that actually caught us out, and it is not in the
// source at all — it is the SDK version stamped in the Mach-O header. AppKit
// reads that to decide which era of controls to draw, so a binary marked
// `sdk 14.0` is handed macOS 14 controls on macOS 26 no matter what this file
// asks for. See the note in build-app.sh.

enum Liquid {
    /// True when the system draws the material itself — which is also the
    /// signal to stop drawing a substitute for it underneath.
    static var isAvailable: Bool {
        #if LIQUID_GLASS
        if #available(macOS 26.0, *) { return true } else { return false }
        #else
        return false
        #endif
    }
}

#if LIQUID_GLASS
@available(macOS 26.0, *)
private func material(tint: Color?, interactive: Bool) -> Glass {
    // Assembled out here on purpose: `var glass = Glass.regular` written
    // inside a @ViewBuilder makes the builder's result type `()`.
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
#endif

extension View {
    /// The system glass material, in the shape the control already has.
    /// A no-op anywhere it cannot be drawn.
    @ViewBuilder
    func liquid(in shape: some Shape, tint: Color? = nil, interactive: Bool = true) -> some View {
        #if LIQUID_GLASS
        if #available(macOS 26.0, *) {
            glassEffect(material(tint: tint, interactive: interactive), in: shape)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Specular light
//
// Glass has a highlight, and a highlight has a source. Pinning it to the
// pointer is the whole difference between a lit surface and a white gradient
// lying on top of one: move across the control and the light moves with you,
// the way it would if you tilted the thing in your hand.
//
// It exists only while the pointer is inside the control, so nothing is being
// animated when nobody is looking at it. Tracking is instant — the light is
// not chasing the cursor, it is cast by it — and only the fade in and out is
// timed, at 160ms.

extension View {
    /// Put this on a coloured or dark control only. Over a near-white capsule
    /// additive white has nothing left to brighten: it clips, and the pool of
    /// light turns into a grubby square patch with the gradient's own frame
    /// showing at its edges. The glass material's own `interactive()`
    /// highlight already covers those, and covers them better.
    ///
    /// `radius` should match the shape the control is already clipped to.
    /// `spread` is the diameter of the pool: roughly twice a control's height
    /// reads as a source somewhere above the screen, which is where every
    /// other highlight in this app puts it.
    func litByPointer(radius: CGFloat, spread: CGFloat = 64, strength: Double = 0.38, enabled: Bool = true) -> some View {
        modifier(PointerLight(radius: radius, spread: spread, strength: strength, enabled: enabled))
    }
}

private struct PointerLight: ViewModifier {
    let radius: CGFloat
    let spread: CGFloat
    let strength: Double
    let enabled: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var point: CGPoint?

    func body(content: Content) -> some View {
        guard enabled, !reduceTransparency else { return AnyView(content) }
        return AnyView(lit(content))
    }

    private func lit(_ content: Content) -> some View {
        content
            .overlay {
                if let point {
                    RadialGradient(
                        colors: [
                            .white.opacity(strength),
                            .white.opacity(strength * 0.28),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: spread / 2
                    )
                    .frame(width: spread, height: spread)
                    .position(point)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    // Light adds to what is under it rather than covering it,
                    // so the label stays legible with the highlight on top.
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): point = location
                case .ended: point = nil
                }
            }
            // Only arrival and departure are animated. Movement inside the
            // control is not, or the light lags the pointer that casts it.
            .animation(.easeOut(duration: 0.16), value: point == nil)
    }
}

// MARK: - Beam
//
// A band of light crossing a surface. Here it means one thing — a measurement
// is running — and it stops when the measurement does. The determinate fill
// underneath says how far along it is; the beam says it is still moving, which
// a fill creeping across a twelve-second window cannot say on its own.
//
// This is the only looping animation in Headroom, it exists for at most twelve
// seconds at a time, and Reduce Motion removes it and leaves the fill.

struct Beam: View {
    /// One pass. Slower reads as a stall, faster as a barber pole.
    var period: Double = 1.6

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travelled = false

    /// On a dark ground a beam is light, added. On a near-white ground there
    /// is nothing left to add — white over white clips to a pale smear you
    /// cannot track — so the band is the accent hue laid over the surface
    /// instead. Same gesture, the physics each ground actually has.
    private var dark: Bool { scheme == .dark }
    private var tint: Color { dark ? .white : Ink.accent }
    private var strength: Double { dark ? 0.28 : 0.32 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let band = max(width * 0.4, 36)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: tint.opacity(strength), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: travelled ? width : -band)
            .blendMode(dark ? .plusLighter : .normal)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    travelled = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}
