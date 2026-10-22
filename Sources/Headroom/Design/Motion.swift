import SwiftUI

/// Native SwiftUI defaults. No continuous decorative animation; readings
/// settle only when a sample changes. Navigation and keyboard input are instant.
enum Motion {
    static let hover = Animation.easeOut(duration: 0.09)
    static let press = Animation.easeOut(duration: 0.07)
    static let reading = Animation.spring(duration: 0.28, bounce: 0)
    static let reveal = Animation.spring(duration: 0.24, bounce: 0)
    static let leave = Animation.easeOut(duration: 0.16)
    static let arrive = Animation.spring(duration: 0.28, bounce: 0.08)
    static let rise: CGFloat = 4
    static let reorder = Animation.spring(duration: 0.25, bounce: 0)
}

extension View {
    /// Honours Reduce Motion by dropping to a crossfade rather than to nothing:
    /// a change with no transition at all is harder to follow, not easier.
    func motion(_ animation: Animation, reduced: Bool) -> some View {
        transaction { $0.animation = reduced ? .easeOut(duration: 0.12) : animation }
    }
}
