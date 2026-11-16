import SwiftUI
import UIKit

/// One coordinate system for the source and its reflected upper edge. The texture
/// matches at the join; blur only increases as it travels away from the real image.
struct PlayerArtworkTopExtension: View {
    let image: UIImage
    let size: CGSize
    let frame: CGRect

    var body: some View {
        plate
            .overlay {
                if frame.minY > 0 {
                    plate
                        .blur(radius: size.width * PlayerArtworkComposition.extensionBlurFraction)
                        .mask {
                            let edge = frame.minY / max(size.height, 1)
                            LinearGradient(stops: (0...8).map { step in
                                let fraction = Double(step) / 8
                                return Gradient.Stop(color: .white.opacity(1 - Self.smoothstep(fraction)),
                                                     location: edge * CGFloat(fraction))
                            } + [.init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                }
            }
    }

    private var plate: some View {
        Canvas { context, _ in
            guard frame.width > 0, frame.height > 0 else { return }
            let source = context.resolve(Image(uiImage: image).interpolation(.high))
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            let count = min(Int(ceil(max(frame.minY, 0) / frame.height)), PlayerArtworkComposition.maximumUpperReflections)
            for index in (0..<count).reversed() {
                let tile = PlayerArtworkComposition.upperTile(index: index, frame: frame)
                var reflected = context
                if index.isMultiple(of: 2) {
                    reflected.translateBy(x: 0, y: tile.minY + tile.maxY)
                    reflected.scaleBy(x: 1, y: -1)
                }
                reflected.draw(source, in: tile)
            }
            context.draw(source, in: frame)
        }
        .frame(width: size.width, height: size.height)
    }

    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}
