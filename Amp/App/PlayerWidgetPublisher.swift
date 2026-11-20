import SwiftUI
import UIKit
import WidgetKit

@MainActor
enum PlayerWidgetPublisher {
    private static var previous: PlayerWidgetSnapshot?
    private static var previousImage: UIImage?
    private(set) static var lastError: String?

    static func publish(song: Song?, playing: Bool, positionMs: Int64 = 0, durationMs: Int64? = nil,
                        waveform: [UInt8]? = nil, forceReload: Bool = false) {
        guard let folder = PlayerWidgetSnapshot.folder else {
            lastError = "The installed signature does not provide a shared App Group for amp and its widget. Preserve the extension and provision the same group for both when signing."
            return
        }
        if previous == nil { previous = PlayerWidgetSnapshot.load() }
        let image = song.flatMap { ArtworkLoader.shared.cachedImage(for: $0.url, maxPixels: 600, fallbackSizes: [1200, 400, 300, 150, 120, 80]) }
        var value = PlayerWidgetSnapshot(title: song?.title ?? "amp", artist: song?.artist ?? "Open your music",
                                         isPlaying: playing, songID: song?.id, hasArtwork: image != nil)
        value.album = song?.album
        value.durationMs = durationMs ?? song?.durationMs
        value.positionMs = positionMs
        let ext = song?.url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        value.formatBadge = ext.isEmpty ? nil : ext
        value.waveform = waveform
        value.artworkFileName = previous?.songID == song?.id ? previous?.artworkFileName : nil
        if let song, let image {
            if previous?.songID == song.id, image === previousImage, let existing = previous?.palette {
                value.palette = existing
            } else {
                value.palette = makePalette(for: song, image: image)
            }
        }
        value = value.retainingArtwork(from: previous) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let now = Date()
        let elapsed = previous?.isPlaying == true ? now.timeIntervalSince(previous?.updatedAt ?? now) * 1000 : 0
        let expected = Double(previous?.positionMs ?? positionMs) + elapsed
        let seeked = abs(Double(positionMs) - expected) > 2000
        guard forceReload || !value.samePlaybackState(as: previous) || image !== previousImage || seeked else { return }
        value.updatedAt = now
        do {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
            if image !== previousImage || (image != nil && value.artworkFileName == nil) {
                if let image, let data = thumbnail(image).jpegData(compressionQuality: 0.6) {
                    let name = "cover-\(UUID().uuidString).jpg"
                    try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    value.artworkFileName = name
                } else {
                    value.hasArtwork = value.artworkFileName != nil
                }
            }
            // Commit metadata only after its own uniquely named artwork has been written.
            let data = try JSONEncoder().encode(value)
            try data.write(to: folder.appendingPathComponent("player.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try? data.write(to: folder.appendingPathComponent("player-last-good.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            previous = value
            previousImage = image
            lastError = nil
            for kind in PlayerWidgetSnapshot.playbackKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
            pruneArtwork(in: folder, keeping: value.artworkFileName)
        } catch {
            lastError = "Couldn't share the current song with the widget: \(error.localizedDescription)"
        }
    }

    private static func makePalette(for song: Song, image: UIImage) -> WidgetArtworkPalette {
        let sampled: LyricsPalette
        if let cached = LyricsPaletteCache.shared.cachedPalette(for: song.url) {
            sampled = cached
        } else if let cgImage = image.cgImage, let pixels = samplePixels(cgImage) {
            sampled = LyricsPalette.fromPixels(pixels)
        } else {
            return .fallback
        }
        let dark = sampled.forScheme(.dark)
        let light = sampled.forScheme(.light)
        let surfaceHsl = hslOf(dark.surface)
        let deepHsl = hslOf(dark.cardGradient.last ?? dark.surface)
        let neutral = surfaceHsl.s < 0.08
        let bleedSat: Float = neutral ? 0 : min(max(surfaceHsl.s * 1.15, 0.16), 0.42)
        let bleedDeepSat: Float = neutral ? 0 : min(max(deepHsl.s * 1.05, 0.14), 0.35)
        let bleed = hslToArgb(surfaceHsl.h, bleedSat, 0.22)
        let bleedDeep = hslToArgb(deepHsl.h, bleedDeepSat, 0.11)
        return WidgetArtworkPalette(dark: tone(dark), light: tone(light), bleed: bleed, bleedDeep: bleedDeep)
    }

    private static func tone(_ palette: LyricsPalette) -> WidgetTonePalette {
        WidgetTonePalette(
            cardTop: palette.cardGradient.first ?? palette.surface,
            surface: palette.surface,
            cardBottom: palette.cardGradient.last ?? palette.surface,
            content: palette.content,
            secondary: palette.secondary,
            accent: palette.accent,
            rim: palette.rim,
            buttonFill: palette.buttonFill,
            onButtonFill: palette.onButtonFill
        )
    }

    private static func samplePixels(_ image: CGImage) -> [UInt32]? {
        let size = 32
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }
        var pixels: [UInt32] = []
        pixels.reserveCapacity(size * size)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = UInt32(rgba[i + 3]) << 24
            let red = UInt32(rgba[i]) << 16
            let green = UInt32(rgba[i + 1]) << 8
            pixels.append(alpha | red | green | UInt32(rgba[i + 2]))
        }
        return pixels
    }

    private static func thumbnail(_ image: UIImage) -> UIImage {
        let scale = min(360 / max(image.size.width, image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private static func pruneArtwork(in folder: URL, keeping current: String?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func modified(_ url: URL) -> Date {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }
        let covers = files.filter { $0.lastPathComponent.hasPrefix("cover-") && $0.pathExtension == "jpg" }
            .sorted { modified($0) > modified($1) }
        // WidgetKit may retain an older timeline while refreshes are budgeted. Do not
        // invalidate its cover just because four more tracks have played.
        let oldestAllowed = Date().addingTimeInterval(-24 * 60 * 60)
        for old in covers.dropFirst(16) where old.lastPathComponent != current && modified(old) < oldestAllowed {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
