import SwiftUI
import UIKit

/// Only the original photo is painted. Above it, cached edge colours provide a
/// continuation without mirrored flowers, faces, lettering, or stretched pixels.
struct PlayerArtworkTopExtension: View {
    let image: UIImage
    let palette: PlayerArtworkChromaticEdge
    let size: CGSize
    let frame: CGRect

    static func blendHeight(frame: CGRect) -> CGFloat { min(frame.width * 0.05, frame.height * 0.18) }
    static func needsExtension(frame: CGRect) -> Bool { frame.minY > 0.5 }

    var body: some View {
        let blend = Self.blendHeight(frame: frame)
        ZStack(alignment: .top) {
            if Self.needsExtension(frame: frame) {
                ZStack {
                    LinearGradient(colors: palette.colors, startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [palette.averageColor.opacity(PlayerArtworkChromaticEdge.topAverageWeight),
                                            palette.averageColor.opacity(0)], startPoint: .top, endPoint: .bottom)
                }
                .frame(width: size.width, height: frame.minY + blend)
            }
            Image(uiImage: image).resizable().interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .mask {
                    if Self.needsExtension(frame: frame) {
                        let end = blend / max(frame.height, 1)
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .white.opacity(0.15625), location: end * 0.25),
                                               .init(color: .white.opacity(0.5), location: end * 0.5),
                                               .init(color: .white.opacity(0.84375), location: end * 0.75),
                                               .init(color: .white, location: end),
                                               .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom)
                    } else { Color.white }
                }
                .position(x: frame.midX, y: frame.midY)
        }
        .frame(width: size.width, height: size.height)
    }
}
