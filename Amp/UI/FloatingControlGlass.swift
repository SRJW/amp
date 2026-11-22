import SwiftUI

/// Apply native interactive glass to the control itself, so the system receives
/// its touches. A detached, non-hit-testable background cannot provide this response.
struct FloatingControlGlass: ViewModifier {
    let enabled: Bool
    var active = true
    let cornerRadius: CGFloat
    var verticalOutset: CGFloat = 0
    var surfaceOpacity: Double = 1

    @ViewBuilder func body(content: Content) -> some View {
        if active && surfaceOpacity >= 1 {
            content
                .padding(.vertical, verticalOutset)
                .glassSurface(cornerRadius: cornerRadius, enabled: enabled, interactive: true)
                .padding(.vertical, -verticalOutset)
                .transition(.identity)
        } else if active && surfaceOpacity > 0 {
            // During the existing player dissolve, fade only the material. The
            // single icon row keeps its interpolated colours and fixed coordinates.
            content.padding(.vertical, verticalOutset)
                .background {
                    Color.clear.glassSurface(cornerRadius: cornerRadius, enabled: enabled)
                        .opacity(surfaceOpacity).allowsHitTesting(false)
                }
                .padding(.vertical, -verticalOutset)
                .transition(.identity)
        } else {
            content.transition(.identity)
        }
    }
}

/// Keep the hit target, icon size and centre fixed during a press. The native
/// glass supplies refraction/deformation; ink only changes intensity slightly.
struct FloatingControlPressStyle: ButtonStyle {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled && configuration.isPressed ? 0.74 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.08 : 0.18),
                       value: configuration.isPressed)
    }
}
