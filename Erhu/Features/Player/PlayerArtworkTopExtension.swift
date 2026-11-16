import SwiftUI
import UIKit

enum PlayerArtworkUpperEdge {
    static let depthW: CGFloat = 0.02

    /// Crop once on track load. Keeping only the real edge avoids reflecting a second logo.
    static func make(from image: UIImage) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let height = min(max(Int(ceil(CGFloat(source.width) * depthW)), 1), source.height)
        guard let edge = source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: height)) else { return nil }
        return UIImage(cgImage: edge, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// One coordinate system for the source and its extended upper edge. The texture
/// matches at the join; blur only increases as it travels away from the real image.
struct PlayerArtworkTopExtension: View {
    let image: UIImage
    let upperEdge: UIImage?
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
            if frame.minY > 0, let upperEdge {
                let edge = context.resolve(Image(uiImage: upperEdge).interpolation(.high))
                var reflected = context
                reflected.translateBy(x: 0, y: frame.minY)
                reflected.scaleBy(x: 1, y: -1)
                reflected.draw(edge, in: CGRect(x: frame.minX, y: 0, width: frame.width, height: frame.minY))
            }
            context.draw(source, in: frame)
        }
        .frame(width: size.width, height: size.height)
    }

    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}
