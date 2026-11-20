import SwiftUI

struct PlayerArtworkPresenceKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}
private struct PlayerArtworkPresentKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var playerArtworkPresent: Bool {
        get { self[PlayerArtworkPresentKey.self] }
        set { self[PlayerArtworkPresentKey.self] = newValue }
    }
    var playerForegroundInk: Color {
        !playerArtworkPresent && colorScheme == .light ? .black : .white
    }
}

/// A deliberate empty-artwork treatment, without any image, blur or colour gradient.
struct PlayerMissingArtworkBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            (scheme == .light ? Color.white : Color.black)
                .overlay {
                    Text("amp").font(.system(size: min(geometry.size.width * 0.25, 120), weight: .heavy))
                        .tracking(-3).foregroundStyle((scheme == .light ? Color.black : .white).opacity(0.065))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.30)
                }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
