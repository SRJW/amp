import SwiftUI
import UIKit
import Observation
import XCTest
@testable import Erhu

/// Render the production containers, rather than accepting a mathematically correct frame
/// while its pixels are clipped, covered by a sibling, or collapsed to a tiny ideal size.
final class PlayerRenderingTests: XCTestCase {
    // Semantic SwiftUI red/blue are platform colours, not unit RGB primaries.
    // Use explicit primaries for assertions about blend weights and coverage.
    private let blendRed = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    private let blendBlue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)
    @MainActor
    func testFullBleedCoverPreservesEdgesAndDissolvesIntoMutedBackground() async throws {
        let url = TagFixtures.write(TagFixtures.mp3(v4: true), name: "player-cover-composition.mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 90, y: 0, width: 10, height: 100))
        }
        var edit = TagWriteRequest()
        edit.artwork = try XCTUnwrap(image.pngData())
        try TagWriter.write(edit, to: url)
        ArtworkLoader.shared.forget(path: url.path)
        _ = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
        let upperPalette = PlayerArtworkChromaticEdge(image: image)
        let backdrop = PlayerFullBleedBackground(dominant: Color(.sRGB, red: 0, green: 0, blue: 1),
                                                statusProfile: PlayerArtworkStatusProfile(image: image, dominant: 0xFF0000FF)) {
            GeometryReader { geometry in
                ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                  size: geometry.size, overscan: PlayerArtworkComposition.transitionOverscan) {
                    PlayerAdaptiveArtwork(image: image, size: geometry.size, safeAreaTop: 0, immersive: true, upperPalette: upperPalette)
                }
            }
        }
        let rendered = try pixels(backdrop.environment(\.colorScheme, .dark), size: CGSize(width: 200, height: 500))
        assertColor(rendered, at: CGPoint(x: 8, y: 100), dominant: 0)
        assertColor(rendered, at: CGPoint(x: 192, y: 100), dominant: 1)
        assertColor(rendered, at: CGPoint(x: 100, y: 100), dominant: 2)
        XCTAssertLessThan(rendered.color(x: 36, y: 10)[2], rendered.color(x: 36, y: 100)[2],
                          "The upper scrim must darken the image behind system status text")
        let belowCover = rendered.color(x: 100, y: 300)
        let bottom = rendered.color(x: 100, y: 480)
        XCTAssertGreaterThan(belowCover[2], belowCover[0], "The muted background must retain the artwork hue")
        XCTAssertGreaterThan(belowCover[0], 0.02, "Desaturation introduces neutral channels; the background is not pure blue")
        XCTAssertLessThan(bottom.max() ?? 1, belowCover.max() ?? 0, "The background darkens towards the home indicator")
        XCTAssertLessThan(bottom.max() ?? 1, 0.30)

    }

    func testArtworkFramingPreservesEveryAspectRatioAndUsesOnlyAvailableHeadroom() {
        for viewport in [CGSize(width: 375, height: 367), CGSize(width: 393, height: 469), CGSize(width: 430, height: 512)] {
            for source in [CGSize(width: 500, height: 500), CGSize(width: 1000, height: 1000),
                           CGSize(width: 2000, height: 2000), CGSize(width: 2000, height: 1000), CGSize(width: 1000, height: 1800)] {
                for rect in [PlayerArtworkComposition.mainFrame(image: source, viewport: viewport, safeAreaTop: 59),
                             PlayerArtworkComposition.playerFrame(image: source, viewport: viewport)] {
                XCTAssertEqual(rect.width / rect.height, source.width / source.height, accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(rect.minX, -0.001)
                XCTAssertGreaterThanOrEqual(rect.minY, -0.001)
                XCTAssertLessThanOrEqual(rect.maxX, viewport.width + 0.001)
                XCTAssertLessThanOrEqual(rect.maxY, viewport.height + 0.001)
                XCTAssertTrue(abs(rect.width - viewport.width) < 0.001 || abs(rect.height - viewport.height) < 0.001)
                }
            }
        }
    }

    @MainActor func testNowPlayingKeepsArtworkBehindStatusWithoutAFullWidthStripInEitherAppearance() throws {
        let screen = CGSize(width: 200, height: 500)
        for (scheme, color) in [(ColorScheme.light, UIColor.black), (.dark, .white)] {
        let view = PlayerFullBleedBackground(dominant: blendBlue,
                                            statusProfile: PlayerArtworkStatusProfile(solid: color),
                                            safeAreaTop: 30) { Color(uiColor: color) }
            .environment(\.colorScheme, scheme)
        let rendered = try pixels(view, size: screen)
        XCTAssertEqual(rendered.color(x: 100, y: 15)[0], scheme == .light ? 0 : 1, accuracy: 0.02,
                       "The artwork between the system indicators must remain visible without a full-width tint")
        for x in [36, 168] {
            let rgb = rendered.color(x: x, y: 15)
            let luminance = PlayerArtworkStatusProfile.luminance(SIMD3(rgb[0], rgb[1], rgb[2]))
            let contrast = scheme == .light ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.4, "Local protection must keep either system ink legible")
        }
        }
        let source = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 20))
        }
        let cover = ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                      size: CGSize(width: 200, height: 280), overscan: PlayerArtworkComposition.transitionOverscan) {
            PlayerAdaptiveArtwork(image: source, size: CGSize(width: 200, height: 280), safeAreaTop: 0, immersive: true,
                                  upperPalette: PlayerArtworkChromaticEdge(image: source))
        }
        let top = try pixels(cover, size: CGSize(width: 200, height: 280))
        let edge = PlayerArtworkComposition.playerFrame(image: source.size, viewport: CGSize(width: 200, height: 280)).minY
        assertColor(top, at: CGPoint(x: 100, y: edge - 1), dominant: 2)
    }

    @MainActor func testNowPlayingDissolveReachesTheTitleWithoutMovingTheContent() throws {
        for screen in [CGSize(width: 200, height: 500), CGSize(width: 240, height: 460)] {
            let view = PlayerFullBleedBackground(dominant: blendBlue,
                                                statusProfile: PlayerArtworkStatusProfile(solid: .red)) { self.blendRed }
                .environment(\.colorScheme, .dark)
            let rendered = try pixels(view, size: screen)
            let background = try pixels(PlayerFullBleedBackground(dominant: blendBlue) { Color.clear }
                .environment(\.colorScheme, .dark), size: screen)
            let nearTitle = rendered.color(x: Int(screen.width / 2), y: Int(screen.height * 0.56))
            let atTitle = rendered.color(x: Int(screen.width / 2), y: Int(screen.height * 0.60))
            let titleBackground = background.color(x: Int(screen.width / 2), y: Int(screen.height * 0.60))
            XCTAssertGreaterThan(nearTitle[0], atTitle[0] + 0.08,
                                 "The cover must continue beyond its old 55% limit and finish beside the unchanged title")
            for channel in 0..<3 {
                XCTAssertEqual(atTitle[channel], titleBackground[channel], accuracy: 0.02,
                               "The image must finish before it can obscure the title")
            }
        }
    }

    @MainActor func testUpperArtworkEdgeDissolvesWithoutAVisibleLineAcrossContrastingCovers() throws {
        let size = CGSize(width: 200, height: 300)
        let cases: [(UIColor, UIColor, [Double])] = [(.white, .black, [0, 0, 0]),
                                                    (.black, .white, [1, 1, 1]),
                                                    (.magenta, .blue, [0, 0, 1])]
        for (edge, base, rgb) in cases {
            let source = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
                base.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
                edge.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 8))
            }
            let view = ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                         size: size, overscan: PlayerArtworkComposition.transitionOverscan) {
                PlayerAdaptiveArtwork(image: source, size: size, safeAreaTop: 0, immersive: true,
                                      upperPalette: PlayerArtworkChromaticEdge(image: source))
            }
            let rendered = try pixels(view, size: size)
            let frame = PlayerArtworkComposition.playerFrame(image: source.size, viewport: size)
            var previous = rendered.color(x: 100, y: Int(frame.minY) - 3)
            for y in (Int(frame.minY) - 2)...(Int(frame.minY) + 6) {
                let current = rendered.color(x: 100, y: y)
                for channel in 0..<3 {
                    XCTAssertLessThan(abs(current[channel] - previous[channel]), 0.06,
                                      "The sharp cover's upper edge must merge gradually into its own extension")
                }
                previous = current
            }
            let blended = rendered.color(x: 100, y: Int(frame.minY) + 8)
            XCTAssertGreaterThan(zip(blended, rgb).map { abs($0 - $1) }.reduce(0, +), 0.05,
                                 "The upper image must still be present inside the fade")
            let interior = rendered.color(x: 100, y: Int(frame.midY))
            for channel in 0..<3 {
                XCTAssertEqual(interior[channel], rgb[channel], accuracy: 0.03,
                               "The upper treatment must not tint the main image below the blend")
            }
        }
    }

    @MainActor func testStatusProtectionSupportsWhiteInkOnWhiteArtAndBlackInkOnBlackArt() throws {
        for (scheme, color) in [(ColorScheme.dark, UIColor.white), (.light, UIColor.black)] {
            let source = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
                (scheme == .dark ? UIColor.black : UIColor.white).setFill()
                context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
            }
            let profile = PlayerArtworkStatusProfile(image: source)
            let view = ZStack(alignment: .top) {
                Color(uiColor: color)
                PlayerArtworkStatusGradient(current: profile, next: nil, blend: 0,
                                            size: CGSize(width: 200, height: 500), safeAreaTop: 30)
            }.environment(\.colorScheme, scheme)
            let rendered = try pixels(view, size: CGSize(width: 200, height: 500))
            let rgb = rendered.color(x: 100, y: 15)
            let luminance = PlayerArtworkStatusProfile.luminance(SIMD3(rgb[0], rgb[1], rgb[2]))
            let contrast = scheme == .dark ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05
            XCTAssertGreaterThanOrEqual(contrast, 4.4)
            XCTAssertEqual(rendered.color(x: 100, y: 100)[0], scheme == .dark ? 1 : 0, accuracy: 0.02,
                           "The status gradient must disappear before the main cover content")
        }
    }

    @MainActor func testChromaticUpperFieldRejectsForegroundFlowersAndPreservesThePhoto() throws {
        let size = CGSize(width: 200, height: 300)
        let cream = UIColor(red: 0.93, green: 0.91, blue: 0.80, alpha: 1)
        let source = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            cream.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            UIColor(red: 0.65, green: 0.18, blue: 0.36, alpha: 1).setFill()
            for x in [50, 68, 86] { context.cgContext.fillEllipse(in: CGRect(x: x, y: -6, width: 24, height: 24)) }
            UIColor(red: 0.96, green: 0.73, blue: 0.62, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 48, y: 40, width: 70, height: 100))
            ("ALBUM" as NSString).draw(at: CGPoint(x: 4, y: 24), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.black
            ])
        }
        let palette = PlayerArtworkChromaticEdge(image: source)
        let frame = PlayerArtworkComposition.playerFrame(image: source.size, viewport: size)
        let view = ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                     size: size, overscan: PlayerArtworkComposition.transitionOverscan) {
            PlayerAdaptiveArtwork(image: source, size: size, safeAreaTop: 0, immersive: true, upperPalette: palette)
        }
        let actual = try pixels(view, size: size)
        for x in [20, 100, 180] {
            for y in [8, 30, 55] {
                let value = actual.color(x: x, y: y)
                for (channel, expected) in [0.93, 0.91, 0.80].enumerated() {
                    XCTAssertEqual(value[channel], expected, accuracy: 0.065,
                                   "The cream background must continue above the flowers without a pink reflected object")
                }
            }
        }
        let detail = actual.color(x: 100, y: Int(frame.minY + PlayerArtworkTopExtension.blendHeight(frame: frame)) + 2)
        XCTAssertLessThan(detail[1], 0.35, "The original flowers must remain visible inside the photograph")
        let legacy = ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                       size: size, overscan: PlayerArtworkComposition.transitionOverscan) {
            PlayerAdaptiveArtwork(image: source, size: size, safeAreaTop: frame.minY)
        }
        let before = try pixels(legacy, size: size)
        for fraction in [0.4, 0.7, 0.9, 0.98] {
            let y = Int(frame.minY + frame.height * fraction)
            for x in [30, 100, 170] {
                for channel in 0..<3 {
                    XCTAssertEqual(actual.color(x: x, y: y)[channel], before.color(x: x, y: y)[channel], accuracy: 0.025,
                                   "The lower artwork and its existing dissolve must remain unchanged")
                }
            }
        }
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "chromatic-cream-edge-without-flower-duplication"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testChromaticEdgeRetainsDarkBackgroundsAndMultipleEdgeColours() throws {
        let dark = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            UIColor(white: 0.02, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            ("GOLD" as NSString).draw(at: CGPoint(x: 12, y: -6), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.yellow
            ])
        }
        let darkPalette = PlayerArtworkChromaticEdge(image: dark)
        for value in darkPalette.rgb {
            XCTAssertLessThan(max(value.x, value.y, value.z), 0.10, "Gold lettering must not turn a dark upper edge into a gold band")
        }
        let multicolour = UIGraphicsImageRenderer(size: CGSize(width: 150, height: 150)).image { context in
            for (index, colour) in [UIColor.red, .green, .blue].enumerated() {
                colour.setFill(); context.fill(CGRect(x: index * 50, y: 0, width: 50, height: 150))
            }
        }
        let palette = PlayerArtworkChromaticEdge(image: multicolour)
        let left = palette.sample(x: 0.05, y: 0.8)
        let middle = palette.sample(x: 0.5, y: 0.8)
        let right = palette.sample(x: 0.95, y: 0.8)
        XCTAssertGreaterThan(left.x, left.z + 0.4)
        XCTAssertGreaterThan(middle.y, max(middle.x, middle.z) + 0.3)
        XCTAssertGreaterThan(right.z, right.x + 0.4)
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 200)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 200))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 20))
        }
        let covered = PlayerAdaptiveArtwork(image: portrait, size: CGSize(width: 200, height: 300), safeAreaTop: 0,
                                            immersive: true, upperPalette: PlayerArtworkChromaticEdge(solid: SIMD3(0, 0, 1)))
        let image = try pixels(covered, size: CGSize(width: 200, height: 300))
        assertColor(image, at: CGPoint(x: 100, y: 2), dominant: 0)
    }

    @MainActor func testPlayerSurfaceDissolvesWithoutScalingOrExposingScreenEdges() throws {
        let size = CGSize(width: 200, height: 300)
        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1] {
            let view = ZStack {
                blendRed
                blendBlue.modifier(PlayerPresentationOpacity(progress: progress, meter: PlayerProgressMeter()))
            }
            let image = try pixels(view, size: size)
            let expected = PlayerCoverGeometry.chromeOpacity(progress)
            for point in [CGPoint(x: 1, y: 1), CGPoint(x: 100, y: 150), CGPoint(x: 198, y: 298)] {
                let value = image.color(x: Int(point.x), y: Int(point.y))
                XCTAssertEqual(value[2], expected, accuracy: 0.025)
                XCTAssertEqual(value[0] + value[2], 1, accuracy: 0.025,
                               "The two stationary surfaces must blend across the whole screen without an exposed border")
            }
        }
    }

    @MainActor func testUpperExtensionDoesNotStretchLocalizedFeaturesIntoVerticalTrails() throws {
        let size = CGSize(width: 200, height: 300)
        for background in [UIColor.black, .white] {
            let source = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
                background.setFill(); context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
                for (index, color) in [UIColor.red, .green, .blue].enumerated() {
                    color.setFill()
                    context.cgContext.fillEllipse(in: CGRect(x: 25 + index * 32, y: -7, width: 14, height: 14))
                }
            }
            let frame = PlayerArtworkComposition.playerFrame(image: source.size, viewport: size)
            let view = ArtworkSlideLayer(progress: 1, direction: 1, incoming: false, reduceMotion: true,
                                         size: size, overscan: PlayerArtworkComposition.transitionOverscan) {
                PlayerAdaptiveArtwork(image: source, size: size, safeAreaTop: 0, immersive: true,
                                      upperPalette: PlayerArtworkChromaticEdge(image: source))
            }
            let actual = try pixels(view, size: size)
            let base = background.isEqual(UIColor.black) ? 0.0 : 1.0
            for x in [50, 100, 150] {
                for y in [4, 12, 20] {
                    for channel in 0..<3 {
                        XCTAssertEqual(actual.color(x: x, y: y)[channel], base, accuracy: 0.06,
                                       "A small detail at the edge must not become a column reaching the status bar")
                    }
                }
                let detail = actual.color(x: x, y: Int(frame.minY + PlayerArtworkTopExtension.blendHeight(frame: frame)) + 1)
                XCTAssertGreaterThan(detail.map { abs($0 - base) }.max() ?? 0, 0.8,
                                     "The original localized detail must remain intact inside the cover")
            }
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 2
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
            attachment.name = base == 0 ? "upper-localized-details-dark" : "upper-localized-details-light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor func testAlbumMetadataIsBelowTheImageAndEditionIsNotDuplicated() throws {
        let title = "Georgia on My Mind (Remastered) (Remastered)"
        XCTAssertEqual(CollectionDisplayTitle.normalized(title), "Georgia on My Mind (Remastered)")
        XCTAssertEqual(CollectionDisplayTitle.normalized("Record (Deluxe) (Remastered)"), "Record (Deluxe) (Remastered)")
        let view = CollectionHeroLayout(separatesMetadata: true) {
            blendRed
            blendBlue.frame(height: 80)
        }
        let rendered = try pixels(view, size: CGSize(width: 200, height: 360))
        assertColor(rendered, at: CGPoint(x: 100, y: 100), dominant: 0)
        assertColor(rendered, at: CGPoint(x: 100, y: 320), dominant: 2)
    }

    @MainActor
    func testCoverBackgroundActuallyBlendsBothArtworkColours() throws {
        var previousRed = 2.0
        var previousBlue = -1.0
        var endpoints: [[Double]] = []
        for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let view = PlayerFullBleedBackground(dominant: blendRed, secondaryDominant: blendBlue, blend: amount) { Color.clear }
            let rendered = try pixels(view, size: CGSize(width: 200, height: 500))
            let sample = rendered.color(x: 100, y: 300)
            XCTAssertLessThanOrEqual(sample[0], previousRed + 0.02, "The old cover colour must fade: \(sample)")
            XCTAssertGreaterThanOrEqual(sample[2], previousBlue - 0.02, "The next cover colour must enter: \(sample)")
            previousRed = sample[0]; previousBlue = sample[2]
            endpoints.append(sample)
        }
        XCTAssertGreaterThan(endpoints[0][0] - endpoints[4][0], 0.10)
        XCTAssertGreaterThan(endpoints[4][2] - endpoints[0][2], 0.10)
        XCTAssertGreaterThan(endpoints[2][0], 0.10, "Midpoint must retain the outgoing colour")
        XCTAssertGreaterThan(endpoints[2][2], 0.10, "Midpoint must retain the incoming colour")
    }

    @MainActor
    func testPaletteDissolveFormsAGradientFromTheCoverIntoTheControls() throws {
        let size = CGSize(width: 200, height: 500)
        let start = try pixels(PlayerFullBleedBackground(dominant: blendRed, secondaryDominant: blendBlue, blend: 0) { Color.clear }, size: size)
        let middle = try pixels(PlayerFullBleedBackground(dominant: blendRed, secondaryDominant: blendBlue, blend: 0.5) { Color.clear }, size: size)
        let end = try pixels(PlayerFullBleedBackground(dominant: blendRed, secondaryDominant: blendBlue, blend: 1) { Color.clear }, size: size)
        // Normalize against each position's endpoints to exclude the permanent
        // darkening towards the home indicator from the transition measurement.
        func arrival(at y: Int) -> Double {
            let first = start.color(x: 100, y: y)[2]
            let last = end.color(x: 100, y: y)[2]
            return (middle.color(x: 100, y: y)[2] - first) / (last - first)
        }
        XCTAssertGreaterThan(arrival(at: 150), arrival(at: 400) + 0.10,
                             "The new palette must blend gradually from the cover into the lower background")
        XCTAssertGreaterThan(arrival(at: 400), 0.1)
        XCTAssertLessThan(arrival(at: 150), 0.9)
    }

    @MainActor
    func testCoverLayersDissolveAtTheSameVisibleProgress() throws {
        let size = CGSize(width: 200, height: 200)
        let mixed = ZStack {
            Color.black
            ArtworkSlideLayer(progress: 0.5, direction: 1, incoming: false, reduceMotion: false, size: size) { self.blendRed }
            ArtworkSlideLayer(progress: 0.5, direction: 1, incoming: true, reduceMotion: false, size: size) { self.blendBlue }
        }
        let image = try pixels(mixed, size: size)
        let centre = image.color(x: 100, y: 100)
        XCTAssertGreaterThan(centre[0], 0.20, "The departing cover must remain visible: \(centre)")
        XCTAssertGreaterThan(centre[2], 0.40, "The arriving cover must blend over it: \(centre)")
        XCTAssertEqual(centre[0] + centre[2], 1, accuracy: 0.05,
                       "The dissolve must not expose the black backdrop and lose brightness")
        for x in [5, 195] {
            let edge = image.color(x: x, y: 100)
            XCTAssertEqual(edge[0] + edge[2], 1, accuracy: 0.05,
                           "The outgoing cover must keep both edges covered during the dissolve")
        }
        for direction in [-1, 1] {
            let layers = ZStack {
                ArtworkSlideLayer(progress: 0.5, direction: direction, incoming: false, reduceMotion: false, size: size) { self.blendRed }
                ArtworkSlideLayer(progress: 0.5, direction: direction, incoming: true, reduceMotion: false, size: size) { self.blendBlue }
            }
            let rendered = try pixels(layers, size: size)
            for x in [0, 199] {
                XCTAssertEqual(rendered.color(x: x, y: 100)[2], rendered.color(x: 100, y: 100)[2], accuracy: 0.05,
                               "The incoming image must cover both edges during next and previous fades")
            }
        }
    }

    @MainActor
    func testChangingCoverRendersAnIntermediateColourFrame() async throws {
        let folder = LibraryPaths.musicFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = ["blend-red-\(UUID().uuidString).mp3", "blend-blue-\(UUID().uuidString).mp3"]
        let urls = names.map { folder.appendingPathComponent($0) }
        defer { for url in urls { try? FileManager.default.removeItem(at: url) } }
        for (index, url) in urls.enumerated() {
            try TagFixtures.mp3(v4: true).write(to: url)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
                (index == 0 ? UIColor.red : UIColor.blue).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            var request = TagWriteRequest()
            request.artwork = try XCTUnwrap(image.pngData())
            try TagWriter.write(request, to: url)
            ArtworkLoader.shared.forget(path: url.path)
            _ = await ArtworkLoader.shared.image(for: url, maxPixels: 1600)
            _ = await LyricsPaletteCache.shared.palette(for: url)
        }
        let songs = names.enumerated().map { Song(id: Int64(-9500 - $0.offset), title: "Cover fixture", artist: "Local", album: "Fixture", durationMs: 120_000, path: $0.element) }
        let selection = CoverRenderSelection(song: songs[0])
        let player = PlayerController(database: try LibraryDatabase.inMemory(), transitions: TransitionSettingsStore())
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let size = CGSize(width: 200, height: 500)
        let scene = try XCTUnwrap(previous?.windowScene ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let controller = UIHostingController(rootView: CoverRenderHost(selection: selection).environment(player).environment(\.playerReduceMotion, false))
        controller.safeAreaRegions = []
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        window.layoutIfNeeded(); controller.view.layoutIfNeeded()
        @MainActor func sample() throws -> [Double] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.lifetime = .keepAlways
            add(attachment)
            return try rgbaPixels(XCTUnwrap(image.cgImage)).color(x: 100, y: 300)
        }
        try await Task.sleep(for: .milliseconds(250))
        let first = try sample()
        selection.song = songs[1]
        // Sample near the middle of the eased 880 ms fade, not in its slow start.
        try await Task.sleep(for: .milliseconds(440))
        let middle = try sample()
        try await Task.sleep(for: .milliseconds(850))
        let last = try sample()
        XCTAssertGreaterThan(first[0] - last[0], 0.10, "Red cover must change to blue: \(first) -> \(last)")
        XCTAssertGreaterThan(middle[2], first[2] + 0.02, "The actual animation must show blue before settling: \(first), \(middle), \(last)")
        XCTAssertGreaterThan(middle[0], last[0] + 0.02, "The actual animation must retain red at an intermediate frame: \(first), \(middle), \(last)")

    }

    @MainActor @Observable final class CoverRenderSelection {
        var song: Song
        init(song: Song) { self.song = song }
    }
    private struct CoverRenderHost: View {
        let selection: CoverRenderSelection
        var body: some View { ReferencePlayerBackdrop(song: selection.song, artworkDrag: .constant(0)).environment(AppSettings()) }
    }

    func testPlayerDominantColourIsNotReplacedByTheDarkLyricsSurface() {
        let original: UInt32 = 0xFF56_887F
        let pixels = Array(repeating: original, count: 900) + Array(repeating: UInt32(0xFFFF_FFFF), count: 124)
        let palette = LyricsPalette.fromPixels(pixels)
        XCTAssertEqual(palette.artworkDominant, original)
        XCTAssertNotEqual(palette.surface, original)
        XCTAssertEqual(palette.forScheme(.light).artworkDominant, original)
        XCTAssertEqual(palette.forScheme(.dark).artworkDominant, original)
    }

    @MainActor
    func testCachedArtworkIsVisibleOnTheFirstFrameWithoutWaitingForATask() async throws {
        let url = TagFixtures.write(TagFixtures.mp3(v4: true), name: "first-frame-cover.mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        var edit = TagWriteRequest()
        edit.artwork = try XCTUnwrap(image.pngData())
        try TagWriter.write(edit, to: url)
        ArtworkLoader.shared.forget(path: url.path)
        _ = await ArtworkLoader.shared.image(for: url, maxPixels: 600)
        // ImageRenderer does not run .task: this must use the existing 600px cache immediately,
        // even though the full player requests 1200px artwork.
        let rendered = try pixels(SongArtworkView(url: url, maxPixels: 1200), size: CGSize(width: 100, height: 100))
        assertColor(rendered, at: CGPoint(x: 50, y: 50), dominant: 0)
    }

    @MainActor
    func testCarouselActuallyPaintsBothPreviewsAndTheNearestCover() throws {
        let entries = (0..<4).map { QueueEntry(song: testSong(Int64($0 + 1))) }
        var scene = CarouselScene()
        scene.select(CarouselSelection(previous: entries[0], current: entries[1], next: entries[2]))
        let colors = [entries[0].id: Color.red, entries[1].id: .green, entries[2].id: .blue, entries[3].id: .red]
        func strip(_ focus: CGFloat, front: Int) -> some View {
            CarouselStrip(items: scene.items, focus: focus, frontOrdinal: front, stack: 0,
                          viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                          reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(colors[item.entry.id] ?? .white).frame(width: 280, height: 380)
            }
            .background(Color.black)
        }
        let resting = try pixels(strip(0, front: 0), size: CGSize(width: 390, height: 450))
        assertColor(resting, at: CGPoint(x: 5, y: 225), dominant: 0)
        assertColor(resting, at: CGPoint(x: 195, y: 225), dominant: 1)
        assertColor(resting, at: CGPoint(x: 385, y: 225), dominant: 2)
        let forward = try pixels(strip(0.75, front: 1), size: CGSize(width: 390, height: 450))
        assertColor(forward, at: CGPoint(x: 195, y: 225), dominant: 2)
        let reverse = try pixels(strip(0.25, front: 0), size: CGSize(width: 390, height: 450))
        assertColor(reverse, at: CGPoint(x: 195, y: 225), dominant: 1)
        let midpoint = try pixels(strip(0.5, front: 1), size: CGSize(width: 390, height: 450))
        for x in 192...198 {
            XCTAssertLessThan(midpoint.color(x: x, y: 225).max() ?? 1, 0.05, "The two covers must have a visible gap")
        }
        scene.select(CarouselSelection(previous: entries[1], current: entries[2], next: entries[3]))
        scene.settle()
        let afterSkip = try pixels(strip(1, front: 1), size: CGSize(width: 390, height: 450))
        assertColor(afterSkip, at: CGPoint(x: 5, y: 225), dominant: 1)
        assertColor(afterSkip, at: CGPoint(x: 195, y: 225), dominant: 2)
        assertColor(afterSkip, at: CGPoint(x: 385, y: 225), dominant: 0)
    }

    @MainActor
    func testOpeningChromeIsVisibleDuringTheCoverFlight() throws {
        for progress in [CGFloat(0.35), 0.65, 1] {
            let chrome = Color.green.modifier(PlayerChromeOpacity(progress: progress)).background(Color.black)
            let rendered = try pixels(chrome, size: CGSize(width: 100, height: 100))
            let green = rendered.color(x: 50, y: 50)[1]
            XCTAssertGreaterThan(green, 0.15, "Controls must join the entrance, not wait for its completion")
            if progress < 1 { XCTAssertLessThan(green, 0.95) }
        }
    }

    @MainActor
    func testCollapseShowsOnlyFloatingArtworkOverTheLibrary() throws {
        let drag = PlayerDragState()
        drag.setPresented(true, reduceMotion: false)
        drag.finishEntrance()
        drag.update(drag.travel / 2)
        let source = CGRect(x: 55, y: 100, width: 280, height: 280)
        let mini = CGRect(x: 20, y: 745, width: 44, height: 44)
        let content = ZStack {
            Color.blue // The library, underneath the player.
            Color.green.modifier(PlayerCollapseVisibility()) // Carousel paint and backdrop.
            Color.green.frame(width: 300, height: 90).modifier(PlayerChromeFade()) // Transport chrome.
        }
        .overlay {
            PlayerArtworkOverlay(progress: drag.progress, frames: .init(expanded: source, mini: mini)) { Color.red }
        }
        .environment(drag)
        let rendered = try pixels(content, size: CGSize(width: 390, height: 844))
        assertColor(rendered, at: CGPoint(x: (source.midX + mini.midX) / 2, y: (source.midY + mini.midY) / 2), dominant: 0)
        assertColor(rendered, at: CGPoint(x: 350, y: 422), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 195, y: 100), dominant: 2)
    }

    @MainActor
    func testFirstPartOfPullBlendsPlayerAndLibraryInsteadOfCuttingToHome() throws {
        let drag = PlayerDragState()
        drag.setPresented(true, reduceMotion: true)
        drag.finishEntrance(reduceMotion: true)
        drag.update(PlayerDragState.chromeFadeDistance / 4)
        let view = ZStack {
            Color.blue
            Color(red: 0, green: 1, blue: 0).modifier(PlayerCollapseVisibility())
        }.environment(drag)
        let rendered = try pixels(view, size: CGSize(width: 100, height: 100))
        let color = rendered.color(x: 50, y: 50)
        XCTAssertGreaterThan(color[1], 0.5, "A small pull must retain most of the player")
        XCTAssertGreaterThan(color[2], 0.05, "The library must be revealed continuously underneath")
        drag.beginDismissal(reduceMotion: true)
    }

    @MainActor
    func testDepthTurnoverKeepsItsCompactFootprint() throws {
        let items = (-1...1).map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2)))) }
        for focus in [CGFloat(-0.75), -0.25, 0.25, 0.75] {
            let content = CarouselStrip(items: items, focus: focus, frontOrdinal: Int(focus.rounded()), stack: 1,
                                        viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                        reduceMotion: false, meter: CarouselPresentationMeter()) { _ in
                Color.blue.frame(width: 280, height: 380)
            }.background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 390, height: 450))
            assertColor(rendered, at: CGPoint(x: 195, y: 225), dominant: 2)
            XCTAssertLessThan(rendered.color(x: 5, y: 225).max() ?? 1, 0.05)
            XCTAssertLessThan(rendered.color(x: 385, y: 225).max() ?? 1, 0.05)
        }
    }

    @MainActor
    func testDepthCardEmergesFromBehindOnTheAppropriateSide() throws {
        for focus in [CGFloat(-0.5), 0.5] {
            // Isolate the exchanging pair: a third rear cover may legitimately fill their gap.
            let items = [0, focus > 0 ? 1 : -1].map {
                CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2))))
            }
            let content = CarouselStrip(items: items, focus: focus, frontOrdinal: 0, stack: 1,
                                        viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                        reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(item.ordinal == 0 ? Color(red: 0, green: 1, blue: 0) : Color(red: 0, green: 0, blue: 1))
                    .frame(width: 280, height: 380)
            }.background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 390, height: 450))
            assertColor(rendered, at: CGPoint(x: focus > 0 ? 350 : 40, y: 225), dominant: 2)
            assertColor(rendered, at: CGPoint(x: focus > 0 ? 40 : 350, y: 225), dominant: 1)
            XCTAssertLessThan(rendered.color(x: 195, y: 225).max() ?? 1, 0.05,
                              "The cards' rotated edges must clear each other before exchanging depth")
            let outgoingX = 195 + CarouselPose(distance: -focus, width: 280, stack: 1, reduceMotion: false).x
            let incomingX = 195 + CarouselPose(distance: (focus > 0 ? 1 : -1) - focus, width: 280, stack: 1, reduceMotion: false).x
            XCTAssertGreaterThan(rendered.color(x: Int(outgoingX), y: 225)[1], 0.8, "The outgoing card must stay opaque")
            XCTAssertGreaterThan(rendered.color(x: Int(incomingX), y: 225)[2], 0.8, "The incoming card must stay opaque")
        }
    }

    @MainActor
    func testRestingDepthPreviewPaintsTheActualNeighbourArtwork() throws {
        let items = [0, 1].map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 1)))) }
        let view = CarouselStrip(items: items, focus: 0, frontOrdinal: 0, stack: 1,
                                 viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                                 reduceMotion: false, meter: CarouselPresentationMeter()) { item in
            Rectangle().fill(item.ordinal == 0 ? Color.green : Color.blue).frame(width: 280, height: 380)
        }.background(Color.black)
        let rendered = try pixels(view, size: CGSize(width: 390, height: 450))
        assertColor(rendered, at: CGPoint(x: 195, y: 28), dominant: 2)
        assertColor(rendered, at: CGPoint(x: 195, y: 225), dominant: 1)
    }

    @MainActor
    func testDepthCleanupDoesNotVisuallySwapCardsAtTheEndOfASlide() throws {
        let items = (-1...1).map { CarouselScene.Item(ordinal: $0, entry: QueueEntry(song: testSong(Int64($0 + 2)))) }
        func strip(focus: CGFloat, anchor: Int) -> some View {
            CarouselStrip(items: items, focus: focus, frontOrdinal: anchor, stack: 1,
                          viewport: CGSize(width: 390, height: 450), cardSize: CGSize(width: 280, height: 380),
                          reduceMotion: false, meter: CarouselPresentationMeter()) { item in
                Rectangle().fill(item.ordinal == 0 ? Color.green : Color.blue).frame(width: 280, height: 380)
            }.background(Color.black)
        }
        for focus in [CGFloat(-1), -0.75, -0.51, 0.51, 0.75, 1] {
            let before = try pixels(strip(focus: focus, anchor: 0), size: CGSize(width: 390, height: 450))
            let after = try pixels(strip(focus: focus, anchor: focus < 0 ? -1 : 1), size: CGSize(width: 390, height: 450))
            XCTAssertTrue(before.bytes == after.bytes, "Settlement must not switch a still-front outgoing cover for its neighbour")
        }
    }

    @MainActor
    func testCoverPixelsEscapeTheScrollViewportAndLandOnTheMiniPlayer() async throws {
        let source = CGRect(x: 55, y: 100, width: 280, height: 280)
        let mini = CGRect(x: 20, y: 745, width: 44, height: 44)
        for progress in [CGFloat(1), 0.5, 0] {
            let content = ZStack(alignment: .topLeading) {
                Color.black
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Color.gray.frame(width: 280, height: 380).offset(x: 55, y: 100)
                        Color.blue.frame(width: 350, height: 90).offset(x: 20, y: 450)
                    }.frame(width: 390, height: 600, alignment: .topLeading)
                }
                .frame(width: 390, height: 600)
                .clipped()
            }
            .frame(width: 390, height: 844)
            .overlay {
                PlayerArtworkOverlay(progress: progress, frames: PlayerArtworkFrames(expanded: source, mini: mini)) {
                    Color.red
                }
            }
            // ScrollView contains a UIKit-backed scrolling surface. Capture the actual hosted
            // hierarchy, including its controls, rather than ImageRenderer's partial output.
            let rendered = try await windowPixels(content, size: CGSize(width: 390, height: 844))
            let center = CGPoint(x: mini.midX + (source.midX - mini.midX) * progress,
                                 y: mini.midY + (source.midY - mini.midY) * progress)
            assertColor(rendered, at: center, dominant: 0)
            assertColor(rendered, at: CGPoint(x: 350, y: 495), dominant: 2)
        }
    }

    @MainActor
    func testAuditionCursorPaintsOneStraightLineThroughBothWaveforms() throws {
        for fraction in [0.2, 0.5, 0.8] {
            let content = TransitionPlayheadStroke(fraction: fraction).background(Color.black)
            let rendered = try pixels(content, size: CGSize(width: 300, height: 280))
            for y in [15, 70, 140, 210, 265] {
                assertColor(rendered, at: CGPoint(x: fraction * 300, y: Double(y)), dominant: 1)
            }
            let otherX = fraction == 0.5 ? 20 : 150
            let outside = rendered.color(x: otherX, y: 140)
            XCTAssertLessThan(outside.max() ?? 1, 0.05)
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func color(x: Int, y: Int) -> [Double] {
            let start = (y * width + x) * 4
            return (0..<3).map { Double(bytes[start + $0]) / 255 }
        }
    }

    @MainActor
    private func pixels<Content: View>(_ content: Content, size: CGSize) throws -> Pixels {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return try rgbaPixels(image)
    }

    @MainActor
    private func windowPixels<Content: View>(_ content: Content, size: CGSize) async throws -> Pixels {
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: content.ignoresSafeArea())
        controller.safeAreaRegions = []
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.view.bounds.size, size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var captured = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            captured = controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        XCTAssertTrue(captured, "The hosted scroll view must be captured before inspecting its pixels")
        return try rgbaPixels(XCTUnwrap(image.cgImage))
    }

    private func rgbaPixels(_ image: CGImage) throws -> Pixels {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Pixels(bytes: bytes, width: width)
    }

    private func assertColor(_ image: Pixels, at point: CGPoint, dominant: Int,
                             file: StaticString = #filePath, line: UInt = #line) {
        let rgb = image.color(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
        XCTAssertGreaterThan(rgb[dominant], 0.25, "Missing cover/cursor at \(point): \(rgb)", file: file, line: line)
        for component in 0..<3 where component != dominant {
            XCTAssertGreaterThan(rgb[dominant], rgb[component] * 1.4, "Incorrect stacking at \(point): \(rgb)", file: file, line: line)
        }
    }
}
