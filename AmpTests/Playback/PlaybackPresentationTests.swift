import XCTest
@testable import Amp

final class PlaybackPresentationTests: XCTestCase {
    func testDisplayInterpolatesWithinTheAudioBufferAndClampsAtTheEnd() {
        XCTAssertEqual(PlaybackVisualPosition.interpolated(10_000, elapsed: 0.016, duration: 60_000), 10_016)
        XCTAssertEqual(PlaybackVisualPosition.interpolated(10_000, elapsed: 0.033, duration: 60_000), 10_033)
        XCTAssertEqual(PlaybackVisualPosition.interpolated(10_000, elapsed: 5, duration: 60_000), 10_100)
        XCTAssertEqual(PlaybackVisualPosition.interpolated(59_990, elapsed: 0.033, duration: 60_000), 60_000)
        XCTAssertEqual(PlaybackVisualPosition.interpolated(10_000, elapsed: -.infinity, duration: 60_000), 10_000)
        XCTAssertEqual(PlaybackVisualPosition.interpolated(10_000, elapsed: -1, duration: 60_000), 10_000)
    }

    func testScrollingClockMovesBetweenBufferedUpdatesAndResetsForSeeks() {
        var clock = PlaybackDisplayTimeline()
        let entry = UUID()
        var previous: Int64 = 0
        for frame in 0...180 {
            let uptime = Double(frame) / 60
            let audio = Int64(floor(uptime / 0.1) * 100)
            let position = clock.position(audioMs: audio, entry: entry, uptime: uptime, durationMs: 60_000, playing: true)
            if frame > 1 {
                XCTAssertGreaterThan(position - previous, 0, "Every frame advances even between buffers")
                XCTAssertLessThanOrEqual(position - previous, 30, "A buffer update never jumps the drawing by 100 ms")
            }
            previous = position
        }
        XCTAssertLessThan(abs(previous - 3000), 100)
        clock.reset()
        XCTAssertEqual(clock.position(audioMs: 5000, entry: entry, uptime: 4, durationMs: 60_000, playing: true), 5000)
        XCTAssertEqual(clock.position(audioMs: 5020, entry: entry, uptime: 4.1, durationMs: 60_000, playing: false), 5020)
        XCTAssertEqual(clock.position(audioMs: 0, entry: UUID(), uptime: 4.2, durationMs: 60_000, playing: true), 0)
    }

    func testNewBackgroundSettingsPreservePreviouslySavedSliders() throws {
        let json = #"{"fadeStart":0.3,"blur":42,"details":0.7,"intensity":0.8,"saturation":1.5}"#
        var saved = try JSONDecoder().decode(PlayerBackgroundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(saved.fadeStart, 0.3)
        XCTAssertEqual(saved.blur, 42)
        XCTAssertEqual(saved.details, 0.7)
        XCTAssertEqual(saved.gradient, 0)
        saved.gradient = 0.65; saved.gradientColor = 0xFF123456
        let decoded = try JSONDecoder().decode(PlayerBackgroundSettings.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
    }

    func testManualCrossfadeIsIndependentFromAutomaticModeAndKeepsLegacyBehaviour() throws {
        var global = GlobalTransitionSettings()
        global.defaultChoice = .custom(TransitionSpec(durationMs: 5_000))
        let old = try JSONDecoder().decode(GlobalTransitionSettings.self, from: JSONEncoder().encode(global))
        XCTAssertEqual(old.manualSpec?.durationMs, 5_000)
        global.automaticMode = .off
        global.manualMode = .short
        global.shortManualDurationMs = 700
        XCTAssertEqual(global.manualSpec?.durationMs, 700)
        XCTAssertFalse(global.automaticMode!.allows(shuffled: true))
        global.manualMode = .off
        global.automaticMode = .all
        XCTAssertNil(global.manualSpec)
        XCTAssertTrue(global.automaticMode!.allows(shuffled: false))
        XCTAssertFalse(AutomaticCrossfadeMode.shuffled.allows(shuffled: false))
        XCTAssertTrue(AutomaticCrossfadeMode.shuffled.allows(shuffled: true))
        global.masterEnabled = false; global.manualMode = .custom
        XCTAssertNil(global.manualSpec)
    }

    func testArtworkTransportSymbolsContrastWithTheirFill() {
        for color: UInt32 in [0xFFFF3300, 0xFF0066FF, 0xFF00AA55, 0xFFFFFF00, 0xFF000000, 0xFFFFFFFF] {
            let sampled = LyricsPalette.fromPixels(Array(repeating: color, count: 64))
            XCTAssertGreaterThan(relativeLuminance(sampled.forScheme(.light).buttonFill), relativeLuminance(sampled.forScheme(.dark).buttonFill))
            XCTAssertNil(ThemeChoice.artwork.colorScheme, "Artwork colours must follow the iPhone's appearance")
            for palette in [sampled.forScheme(.dark), sampled.forScheme(.light)] {
                XCTAssertGreaterThanOrEqual(contrast(palette.onButtonFill, palette.buttonFill), 4.5)
            }
        }
    }
}
