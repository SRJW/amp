import SwiftUI

/// Apply native interactive glass to the control itself, so the system receives
/// its touches. A detached, non-hit-testable background cannot provide this response.
struct FloatingControlGlass: ViewModifier {
    let enabled: Bool
    var cornerRadius: CGFloat? = nil
    var active = true
    var verticalOutset: CGFloat = 0
    var surfaceOpacity: Double = 1

    @ViewBuilder func body(content: Content) -> some View {
        if active && surfaceOpacity >= 1 {
            surface(content.padding(.vertical, verticalOutset), interactive: true)
                .padding(.vertical, -verticalOutset)
                .transition(.identity)
        } else if active && surfaceOpacity > 0 {
            // During the existing player dissolve, fade only the material. The
            // single icon row keeps its interpolated colours and fixed coordinates.
            content.padding(.vertical, verticalOutset)
                .background {
                    surface(Color.clear, interactive: false)
                        .opacity(surfaceOpacity).allowsHitTesting(false)
                }
                .padding(.vertical, -verticalOutset)
                .transition(.identity)
        } else {
            content.transition(.identity)
        }
    }

    @ViewBuilder private func surface<Control: View>(_ control: Control, interactive: Bool) -> some View {
        if let cornerRadius {
            // Restore the earlier mini-player silhouette, keeping native contact
            // response on the live control rather than a detached background.
            control.glassSurface(cornerRadius: cornerRadius, enabled: enabled, interactive: interactive)
        } else {
            control.glassCapsule(enabled: enabled, interactive: interactive)
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
