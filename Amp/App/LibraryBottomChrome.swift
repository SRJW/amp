import SwiftUI

extension View {
    /// Explicitly clip both material and content, including the mini player's progress line.
    func chromeSurface(enabled: Bool) -> some View {
        glassCapsule(enabled: enabled)
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}
