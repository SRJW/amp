import SwiftUI

/// Only the portrait reacts to scroll geometry. The name, actions and discography
/// keep their normal content positions; no scroll state invalidates the song list.
struct ArtistScrollPortrait<Portrait: View>: View {
    static var coordinateSpace: String { "artist-portrait-scroll" }
    let hasPhoto: Bool
    @ViewBuilder let portrait: () -> Portrait
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ArtistPortraitCanvas(size: geometry.size,
                                 offset: geometry.frame(in: .named(Self.coordinateSpace)).minY,
                                 animated: !reduceMotion, hasPhoto: hasPhoto, portrait: portrait)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One transform for the sharp portrait and its lower mist prevents the two
/// resolutions/crops from drifting apart as the scroll view rubber-bands.
struct ArtistPortraitCanvas<Portrait: View>: View {
    let size: CGSize
    let offset: CGFloat
    var animated = true
    var hasPhoto = true
    @ViewBuilder let portrait: () -> Portrait

    var body: some View {
        let pull = animated ? max(offset, 0) : 0
        let departure = animated ? min(max(-offset / max(size.height, 1), 0), 1) : 0
        let eased = departure * departure * (3 - 2 * departure)
        let parallax = animated ? max(-offset, 0) * 0.25 : 0
        let blur = hasPhoto ? eased * 12 : 0
        ZStack(alignment: .top) {
            portrait()
                .frame(width: size.width, height: size.height + pull)
                .blur(radius: hasPhoto ? 26 : 0)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .white.opacity(0.88), location: 0.60),
                    .init(color: .white.opacity(0.28), location: 0.84),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
            portrait()
                .frame(width: size.width, height: size.height + pull)
                .blur(radius: blur)
                .mask(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.42),
                    .init(color: .white.opacity(0.72), location: 0.56),
                    .init(color: .white.opacity(0.22), location: 0.70),
                    .init(color: .clear, location: 0.84),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
        }
        // The photo stays against the top edge during pull-down; the scroll
        // view's own spring returns it. Never add an animation that lags the finger.
        .offset(y: -pull + parallax)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}
