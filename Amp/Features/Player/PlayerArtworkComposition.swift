import SwiftUI
import UIKit

enum PlayerArtworkComposition {
    static let titleCentreH: CGFloat = 0.60
    static let titleClearanceW: CGFloat = 0.012
    static let contentAlignment: CGFloat = 0.70
    static let transitionOverscan: CGFloat = 1.04
    static let extensionBlurFraction: CGFloat = 0.055
    static let sideFeather = 0.06
    static let topFeather = 0.04
    static let bottomFeather = 0.12

    /// End the dissolve just before the existing title, including its text height.
    static func artworkHeight(in screen: CGSize) -> CGFloat {
        let halfTitle = PlayerButtonConstants.titleSize * PlayerLayoutMetrics.titleScale / 2
        return max(screen.height * titleCentreH - halfTitle - screen.width * titleClearanceW, 0)
    }

    /// Preserve the original aspect ratio. Use available headroom, rather than shifting every cover.
    static func mainFrame(image: CGSize, viewport: CGSize, safeAreaTop: CGFloat) -> CGRect {
        guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / image.width, viewport.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2,
                      y: min(max(safeAreaTop, 0), max(viewport.height - size.height, 0)),
                      width: size.width, height: size.height)
    }

    /// The extension covers y=0; use spare space to lower the sharp image proportionally.
    static func playerFrame(image: CGSize, viewport: CGSize) -> CGRect {
        var rect = mainFrame(image: image, viewport: viewport, safeAreaTop: 0)
        rect.origin.y = max(viewport.height - rect.height, 0) * contentAlignment
        return rect
    }

    static func extensionFrame(image: CGSize, viewport: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(viewport.width / image.width, viewport.height / image.height) * transitionOverscan
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// Both layers reference the same decoded image. Only the soft extension fills and crops.
struct PlayerAdaptiveArtwork: View {
    let image: UIImage
    let size: CGSize
    let safeAreaTop: CGFloat
    var immersive = false
    var upperPalette: PlayerArtworkChromaticEdge? = nil

    var body: some View {
        let rect = immersive ? PlayerArtworkComposition.playerFrame(image: image.size, viewport: size)
            : PlayerArtworkComposition.mainFrame(image: image.size, viewport: size, safeAreaTop: safeAreaTop)
        ZStack {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
                .blur(radius: size.width * PlayerArtworkComposition.extensionBlurFraction, opaque: true)
            ZStack {
                if immersive {
                    PlayerArtworkTopExtension(image: image, palette: upperPalette ?? PlayerArtworkChromaticEdge(solid: SIMD3(repeating: 0.5)),
                                              size: size, frame: rect)
                        .mask {
                            LinearGradient(stops: [.init(color: .white, location: 0),
                                                   .init(color: .white, location: (rect.minY + rect.height * (1 - PlayerArtworkComposition.bottomFeather)) / max(size.height, 1)),
                                                   .init(color: .clear, location: rect.maxY / max(size.height, 1)),
                                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        .mask {
                            if rect.width < size.width - 0.5 {
                                LinearGradient(stops: [.init(color: .clear, location: 0),
                                                       .init(color: .clear, location: rect.minX / size.width),
                                                       .init(color: .white, location: (rect.minX + rect.width * PlayerArtworkComposition.sideFeather) / size.width),
                                                       .init(color: .white, location: (rect.maxX - rect.width * PlayerArtworkComposition.sideFeather) / size.width),
                                                       .init(color: .clear, location: rect.maxX / size.width),
                                                       .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                            } else { Color.white }
                        }
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: rect.width, height: rect.height)
                        .mask(verticalBlend(frame: rect))
                        .mask {
                            if rect.width < size.width - 0.5 {
                                LinearGradient(stops: [.init(color: .clear, location: 0),
                                                       .init(color: .white, location: PlayerArtworkComposition.sideFeather),
                                                       .init(color: .white, location: 1 - PlayerArtworkComposition.sideFeather),
                                                       .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                            } else { Color.white }
                        }
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: size.width, height: size.height)
            // Cancel the transition's seam protection for the content-preserving main layer.
            .scaleEffect(1 / PlayerArtworkComposition.transitionOverscan)
        }
        .frame(width: size.width, height: size.height)
    }

    private func verticalBlend(frame: CGRect) -> LinearGradient {
        let hasHeadroom = frame.minY > 0
        var stops: [Gradient.Stop] = [.init(color: hasHeadroom ? .clear : .white, location: 0)]
        if hasHeadroom {
            stops.append(.init(color: .white, location: PlayerArtworkComposition.topFeather))
        }
        stops.append(.init(color: .white, location: 1 - PlayerArtworkComposition.bottomFeather))
        stops.append(.init(color: .clear, location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// A tiny cached colour map is created on track load, never from a gesture or animation frame.
struct PlayerArtworkStatusProfile {
    let upperPalette: PlayerArtworkChromaticEdge
    private static let side = 16
    private let imageSize: CGSize
    private let pixels: [SIMD3<Double>]
    private let dominant: SIMD3<Double>

    init(image: UIImage, dominant argb: UInt32? = nil) {
        imageSize = image.size
        let base: SIMD3<Double> = argb.map {
            SIMD3(Double(($0 >> 16) & 255), Double(($0 >> 8) & 255), Double($0 & 255)) / 255
        } ?? SIMD3(repeating: 0.5)
        upperPalette = PlayerArtworkChromaticEdge(image: image, fallback: base)
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let cgImage = image.cgImage,
                  let context = CGContext(data: buffer.baseAddress, width: Self.side, height: Self.side,
                                          bitsPerComponent: 8, bytesPerRow: Self.side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(Self.side), height: CGFloat(Self.side)))
            return true
        }
        let colors: [SIMD3<Double>] = (0..<(Self.side * Self.side)).map { index in
            guard rendered else { return base }
            let offset = index * 4
            let rgb = SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
            return rgb + base * (1 - Double(bytes[offset + 3]) / 255)
        }
        pixels = colors
        if argb == nil {
            var sum = SIMD3<Double>(repeating: 0)
            for color in colors { sum += color }
            dominant = sum / Double(colors.count)
        } else { dominant = base }
    }

    init(solid color: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rgb = SIMD3(Double(red), Double(green), Double(blue))
        dominant = rgb
        upperPalette = PlayerArtworkChromaticEdge(solid: rgb)
        imageSize = CGSize(width: 1, height: 1)
        pixels = Array(repeating: rgb, count: Self.side * Self.side)
    }

    func protection(viewport: CGSize, safeAreaTop: CGFloat, scheme: ColorScheme,
                    contentSafeAreaTop: CGFloat? = nil, immersive: Bool = false, falloffHeight: CGFloat? = nil,
                    secondary: PlayerArtworkStatusProfile? = nil, blend: Double = 0) -> PlayerArtworkStatusProtection {
        var samples = statusSamples(viewport: viewport, safeAreaTop: safeAreaTop, contentSafeAreaTop: contentSafeAreaTop,
                                    immersive: immersive, falloffHeight: falloffHeight)
        if let secondary {
            let other = secondary.statusSamples(viewport: viewport, safeAreaTop: safeAreaTop, contentSafeAreaTop: contentSafeAreaTop,
                                                immersive: immersive, falloffHeight: falloffHeight)
            let amount = blend.clamped(0, 1)
            samples = zip(samples, other).map { first, last in
                (first.color + (last.color - first.color) * amount, first.coverage)
            }
        }
        // Tint towards the artwork's hue, choosing light/dark for the existing system ink.
        let tint = scheme == .dark ? dominant * 0.12 : dominant * 0.12 + SIMD3(repeating: 0.88)
        func sufficient(_ opacity: Double) -> Bool {
            samples.allSatisfy { sample in
                let alpha = opacity * sample.coverage
                let luminance = Self.luminance(sample.color * (1 - alpha) + tint * alpha)
                return scheme == .dark ? 1.05 / (luminance + 0.05) >= 4.5 : (luminance + 0.05) / 0.05 >= 4.5
            }
        }
        var low = 0.0, high = 0.72
        if sufficient(low) { high = low }
        else {
            for _ in 0..<9 {
                let middle = (low + high) / 2
                if sufficient(middle) { high = middle } else { low = middle }
            }
        }
        return PlayerArtworkStatusProtection(rgb: tint, opacity: high)
    }

    private func statusSamples(viewport: CGSize, safeAreaTop: CGFloat, contentSafeAreaTop: CGFloat?,
                               immersive: Bool, falloffHeight: CGFloat?) -> [(color: SIMD3<Double>, coverage: Double)] {
        let main = immersive ? PlayerArtworkComposition.playerFrame(image: imageSize, viewport: viewport)
            : PlayerArtworkComposition.mainFrame(image: imageSize, viewport: viewport, safeAreaTop: contentSafeAreaTop ?? safeAreaTop)
        let extended = PlayerArtworkComposition.extensionFrame(image: imageSize, viewport: viewport)
        var samples: [(color: SIMD3<Double>, coverage: Double)] = []
        for x in [0.08, 0.18, 0.28, 0.72, 0.84, 0.94] {
            for y in [0.35, 0.7] {
                let point = CGPoint(x: viewport.width * x, y: safeAreaTop * y)
                let coverage = falloffHeight.map { PlayerStatusFalloff.coverage(y: point.y, band: safeAreaTop, height: $0) } ?? 1
                if immersive {
                    let depth = PlayerArtworkTopExtension.blendHeight(frame: main)
                    if PlayerArtworkTopExtension.needsExtension(frame: main) && point.y < main.minY + depth {
                        let field = upperPalette.sample(x: point.x / max(viewport.width, 1), y: point.y / max(main.minY + depth, 1))
                        let fraction = Double(((point.y - main.minY) / max(depth, 1)).clamped(0, 1))
                        let alpha = fraction * fraction * (3 - 2 * fraction)
                        samples.append((field * (1 - alpha) + sample(point, in: main) * alpha, coverage))
                    } else { samples.append((sample(point, in: main), coverage)) }
                    let side = main.width * PlayerArtworkComposition.sideFeather
                    if main.width < viewport.width - 0.5 && (point.x < main.minX + side || point.x > main.maxX - side) {
                        samples.append((sample(point, in: extended), coverage))
                    } else if let last = samples.last { samples.append(last) }
                } else {
                    samples.append((sample(point, in: extended), coverage))
                    samples.append((main.contains(point) ? sample(point, in: main) : sample(point, in: extended), coverage))
                }
            }
        }
        return samples
    }

    private func sample(_ point: CGPoint, in rect: CGRect) -> SIMD3<Double> {
        guard rect.width > 0, rect.height > 0 else { return dominant }
        let x = min(max(Int((point.x - rect.minX) / rect.width * CGFloat(Self.side)), 0), Self.side - 1)
        let y = min(max(Int((point.y - rect.minY) / rect.height * CGFloat(Self.side)), 0), Self.side - 1)
        return pixels[y * Self.side + x]
    }

    static func luminance(_ rgb: SIMD3<Double>) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return linear(rgb.x) * 0.2126 + linear(rgb.y) * 0.7152 + linear(rgb.z) * 0.0722
    }
}

struct PlayerArtworkStatusProtection {
    let rgb: SIMD3<Double>
    let opacity: Double
}

enum PlayerStatusFalloff {
    static let holdBand: CGFloat = 0.55
    static let reachW: CGFloat = 0.22

    static func coverage(y: CGFloat, band: CGFloat, height: CGFloat) -> Double {
        let start = band * holdBand
        let fraction = Double(((y - start) / max(height - start, 1)).clamped(0, 1))
        return 1 - fraction * fraction * (3 - 2 * fraction)
    }

    static func stops(color: Color, band: CGFloat, height: CGFloat) -> [Gradient.Stop] {
        let start = band * holdBand
        return [.init(color: color, location: 0)] + (0...8).map { step in
            let y = start + (height - start) * CGFloat(step) / 8
            return .init(color: color.opacity(coverage(y: y, band: band, height: height)), location: y / max(height, 1))
        }
    }
}

struct PlayerArtworkStatusGradient: View {
    let current: PlayerArtworkStatusProfile
    let next: PlayerArtworkStatusProfile?
    let blend: Double
    let size: CGSize
    let safeAreaTop: CGFloat
    var artworkHeightFraction: CGFloat? = nil
    var contentSafeAreaTop: CGFloat? = nil
    var localizedProtection = false
    var immersive = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let band = max(safeAreaTop, size.height * 0.045)
        let viewport = CGSize(width: size.width, height: artworkHeightFraction.map { size.height * $0 }
                              ?? PlayerArtworkComposition.artworkHeight(in: size))
        let height = min(band + size.width * (localizedProtection ? PlayerStatusFalloff.reachW : 0.1), size.height * 0.18)
        let falloffHeight = localizedProtection ? height : nil
        let first = current.protection(viewport: viewport, safeAreaTop: band, scheme: scheme, contentSafeAreaTop: contentSafeAreaTop, immersive: immersive, falloffHeight: falloffHeight)
        let last = next?.protection(viewport: viewport, safeAreaTop: band, scheme: scheme, contentSafeAreaTop: contentSafeAreaTop, immersive: immersive, falloffHeight: falloffHeight) ?? first
        let amount = blend.clamped(0, 1)
        let rgb = first.rgb + (last.rgb - first.rgb) * amount
        let opacity = first.opacity + (last.opacity - first.opacity) * amount
        let color = Color(.sRGB, red: rgb.x, green: rgb.y, blue: rgb.z, opacity: opacity)
        LinearGradient(stops: localizedProtection ? PlayerStatusFalloff.stops(color: color, band: band, height: height) : [.init(color: color, location: 0),
                               .init(color: color, location: min(band / max(height, 1), 0.9)),
                               .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .mask {
                if localizedProtection {
                    // Protect the system ink locally in either appearance, without a
                    // full-width tint that reads as a horizontal band on patterned art.
                    LinearGradient(stops: [.init(color: .white, location: 0),
                                           .init(color: .white, location: 0.30),
                                           .init(color: .clear, location: 0.43),
                                           .init(color: .clear, location: 0.57),
                                           .init(color: .white, location: 0.70),
                                           .init(color: .white, location: 1)], startPoint: .leading, endPoint: .trailing)
                } else { Color.white }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Pick native ink first. Only mixed edges that defeat both ink colours need a scrim.
struct PlayerAdaptiveStatusBar: View {
    let current: PlayerArtworkStatusProfile
    let next: PlayerArtworkStatusProfile?
    let blend: Double
    let size: CGSize
    let safeAreaTop: CGFloat

    static func selection(current: PlayerArtworkStatusProfile, next: PlayerArtworkStatusProfile?,
                          blend: Double, size: CGSize, safeAreaTop: CGFloat) -> (scheme: ColorScheme, opacity: Double) {
        let band = max(safeAreaTop, size.height * 0.045)
        let viewport = CGSize(width: size.width, height: PlayerArtworkComposition.artworkHeight(in: size))
        let height = min(band + size.width * PlayerStatusFalloff.reachW, size.height * 0.18)
        let white = current.protection(viewport: viewport, safeAreaTop: band, scheme: .dark,
                                       immersive: true, falloffHeight: height, secondary: next, blend: blend).opacity
        let black = current.protection(viewport: viewport, safeAreaTop: band, scheme: .light,
                                       immersive: true, falloffHeight: height, secondary: next, blend: blend).opacity
        if white == 0 { return (.dark, 0) }
        if black == 0 { return (.light, 0) }
        // Never brighten dark artwork to accommodate dark status text.
        return (.dark, white)
    }

    var body: some View {
        let choice = Self.selection(current: current, next: next, blend: blend, size: size, safeAreaTop: safeAreaTop)
        let band = max(safeAreaTop, size.height * 0.045)
        let height = min(band + size.width * PlayerStatusFalloff.reachW, size.height * 0.18)
        LinearGradient(stops: PlayerStatusFalloff.stops(color: .black.opacity(choice.opacity), band: band, height: height),
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .preference(key: PlayerStatusBarSchemeKey.self, value: choice.scheme)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The album hero uses the same composition, without changing other artwork thumbnails.
struct PlayerAlbumArtwork: View {
    let image: UIImage
    @State private var safeAreaTop: CGFloat = 0
    @State private var profile: PlayerArtworkStatusProfile?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                  size: geometry.size, overscan: PlayerArtworkComposition.transitionOverscan) {
                    PlayerAdaptiveArtwork(image: image, size: geometry.size, safeAreaTop: 0)
                }
                if let profile {
                    PlayerArtworkStatusGradient(current: profile, next: nil, blend: 0,
                                                size: geometry.size, safeAreaTop: safeAreaTop,
                                                artworkHeightFraction: 1, contentSafeAreaTop: 0)
                }
            }
        }
        .background { PlayerArtworkSafeAreaProbe { safeAreaTop = $0 }.frame(width: 0, height: 0) }
        .task(id: ObjectIdentifier(image)) { profile = PlayerArtworkStatusProfile(image: image) }
    }
}

/// Read the real window inset even when the artwork itself intentionally ignores safe areas.
struct PlayerArtworkSafeAreaProbe: UIViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.changed = changed
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.readInsets() }

    final class Probe: UIView {
        var changed: ((CGFloat) -> Void)?
        private var last: CGFloat?
        override func didMoveToWindow() { super.didMoveToWindow(); readInsets() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); readInsets() }
        func readInsets() {
            guard let window, last != window.safeAreaInsets.top else { return }
            let value = window.safeAreaInsets.top
            last = value
            DispatchQueue.main.async { [weak self] in self?.changed?(value) }
        }
    }
}
