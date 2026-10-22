import AppKit
import CoreImage
import SwiftUI

// Craft details. Each one is small enough that nobody will name it, and
// together they are the difference between a window and a made thing.
// https://craft.gustavofior.com

// MARK: - Noise
// https://craft.gustavofior.com/noise
//
// A flat fill is the flattest thing a screen can show. Grain breaks the
// surface into light and dark pixels so the colour has a texture to sit in,
// and it kills the banding that a wide soft gradient always has.
//
// The tile is generated once at launch and then repeated. A live filter over
// a whole window repaints every frame; a tiled image costs nothing after the
// first paint, which is the trade the Craft article recommends for anything
// large or moving.

@MainActor
enum GrainTile {
    static let image: NSImage? = {
        let side = 180
        guard let generator = CIFilter(name: "CIRandomGenerator"),
              let noise = generator.outputImage else { return nil }
        let grey = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let tile = grey.cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        guard let rendered = CIContext().createCGImage(tile, from: tile.extent) else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: side, height: side))
    }()
}

/// Lay this over a surface, never under content that has to be read crisply.
struct Grain: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let tile = GrainTile.image, !reduceTransparency {
            Image(nsImage: tile)
                .resizable(resizingMode: .tile)
                .blendMode(scheme == .dark ? .softLight : .multiply)
                // Dark surfaces take grain more readily than light ones, so
                // the light value is deliberately lower rather than shared.
                .opacity(scheme == .dark ? 0.035 : 0.018)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Image outlines
// https://craft.gustavofior.com/image-outlines
//
// An app icon does not know what is behind it. A pale icon on a pale surface
// has no edge at all. One line drawn *over* the outermost pixels, not around
// them, gives every icon a shape without changing its size.

extension View {
    /// `radius` should match the shape the image is already clipped to.
    func imageOutline(radius: CGFloat, scheme: ColorScheme) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.10),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Press
//
// Pressing something should feel like pressing something. The scale is read
// as a physical push rather than as motion, which is why it stays this small;
// 160ms is the top of the press-feedback budget, and anything slower starts
// to feel like a delay rather than a response.

extension View {
    func pressable(_ pressed: Bool, scale: CGFloat = 0.97) -> some View {
        scaleEffect(pressed ? scale : 1)
            .animation(.easeOut(duration: 0.14), value: pressed)
    }
}

// MARK: - Nested border radius
// https://craft.gustavofior.com/nested-border-radius
//
// Concentric corners share a centre, so an inner curve is the outer curve
// minus the gap between the two edges. Below zero there is no curve left and
// the inner corner is square.

enum Nested {
    static func radius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }
}
