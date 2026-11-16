import SwiftUI
import UIKit

/// Cached colour samples, not an image or a reflected part of the photograph.
struct PlayerArtworkChromaticEdge {
    let rgb: [SIMD3<Double>]
    let colors: [Color]
    let average: SIMD3<Double>
    let averageColor: Color
    static let topAverageWeight = 0.35

    init(solid: SIMD3<Double>) {
        rgb = Array(repeating: solid, count: 5)
        colors = Array(repeating: Self.color(solid), count: 5)
        average = solid
        averageColor = Self.color(solid)
    }

    init(image: UIImage, fallback: SIMD3<Double> = SIMD3(repeating: 0.5)) {
        let width = 40, height = 6
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let source = image.cgImage else { return false }
            let depth = min(source.height, max(1, Int(ceil(Double(min(source.width, source.height)) * 0.025))))
            guard let edge = source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: depth)),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(edge, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            rgb = Array(repeating: fallback, count: 5)
            colors = Array(repeating: Self.color(fallback), count: 5)
            average = fallback
            averageColor = Self.color(fallback)
            return
        }
        var samples: [SIMD3<Double>] = []
        var groups: [Int: [Int]] = [:]
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = Double(bytes[offset + 3]) / 255
            let pixel = SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
            let value = pixel + fallback * (1 - alpha)
            samples.append(value)
            let r = min(Int(value.x * 8), 7), g = min(Int(value.y * 8), 7), b = min(Int(value.z * 8), 7)
            groups[r * 64 + g * 8 + b, default: []].append(index)
        }
        let background = groups.values.max(by: { $0.count < $1.count }) ?? []
        var neutral = SIMD3<Double>(repeating: 0)
        for index in background { neutral += samples[index] }
        neutral = background.isEmpty ? fallback : neutral / Double(background.count)
        var backgroundMembers: [Int] = []
        for (index, value) in samples.enumerated() {
            let delta = value - neutral
            if delta.x * delta.x + delta.y * delta.y + delta.z * delta.z < 0.0196 { backgroundMembers.append(index) }
        }
        let spansLeft = backgroundMembers.contains { $0 % width < width / 4 }
        let spansRight = backgroundMembers.contains { $0 % width >= width * 3 / 4 }
        let channels = [neutral.x, neutral.y, neutral.z]
        let chroma = (channels.max() ?? 0) - (channels.min() ?? 0)
        let neutralBackground = backgroundMembers.count >= width * height * 55 / 100 && spansLeft && spansRight && chroma < 0.22
        var columns: [SIMD3<Double>] = []
        for x in 0..<width {
            var sum = SIMD3<Double>(repeating: 0)
            for y in 0..<height { sum += samples[y * width + x] }
            var value = sum / Double(height)
            if neutralBackground {
                let delta = value - neutral
                let distance = sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
                if distance > 0.05 { value = neutral + delta * (0.05 / distance) }
            }
            columns.append(value)
        }
        var stops: [SIMD3<Double>] = []
        for index in 0..<5 {
            let center = index * (width - 1) / 4
            var sum = SIMD3<Double>(repeating: 0)
            var weight = 0.0
            for x in max(center - 7, 0)...min(center + 7, width - 1) {
                let amount = Double(8 - abs(x - center))
                sum += columns[x] * amount
                weight += amount
            }
            stops.append(sum / weight)
        }
        var mean = SIMD3<Double>(repeating: 0)
        for value in stops { mean += value }
        mean /= Double(stops.count)
        rgb = stops
        colors = stops.map(Self.color)
        average = mean
        averageColor = Self.color(mean)
    }

    func sample(x: CGFloat, y: CGFloat) -> SIMD3<Double> {
        let position = Double(x.clamped(0, 1)) * Double(rgb.count - 1)
        let index = min(Int(position), rgb.count - 2)
        let fraction = position - Double(index)
        let horizontal = rgb[index] + (rgb[index + 1] - rgb[index]) * fraction
        let weight = Self.topAverageWeight * Double(1 - y.clamped(0, 1))
        return horizontal * (1 - weight) + average * weight
    }

    private static func color(_ value: SIMD3<Double>) -> Color {
        Color(.sRGB, red: value.x, green: value.y, blue: value.z, opacity: 1)
    }
}
