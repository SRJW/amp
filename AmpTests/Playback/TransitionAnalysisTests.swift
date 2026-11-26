import AVFoundation
import XCTest
@testable import Amp

final class TransitionAnalysisTests: XCTestCase {
    func testCueWindowsAndAutomationMatchPlaybackPlanner() throws {
        var spec = TransitionSpec.preset(.blend)
        spec.durationMs = 4000
        spec.outgoingCutMs = 7000
        spec.incomingStartMs = 8000
        let timing = try XCTUnwrap(PairTransitionTiming(spec: spec, outgoingMs: 60_000, incomingMs: 90_000))
        XCTAssertEqual(timing.plan.startAtMs, 49_000)
        XCTAssertEqual(timing.outgoingRange, 47_500..<53_000)
        XCTAssertEqual(timing.incomingRange, 8_000..<13_500)
        XCTAssertEqual(timing.totalMs, 7000)
        for time in [0.0, 1000, 2000, 4000] {
            for role in [TransitionRole.outgoing, .incoming] {
                XCTAssertEqual(timing.automation(role).gainAt(time), spec.gain(role, Float(time / 4000)), accuracy: 1e-6)
                XCTAssertEqual(timing.automation(role).bassDbAt(time), spec.bassDb(role, Float(time / 4000)), accuracy: 1e-6)
                XCTAssertEqual(timing.automation(role).filterAt(time), spec.filter.settingAt(role, Float(time / 4000)))
            }
        }
        XCTAssertNil(PairTransitionTiming(spec: spec, outgoingMs: 0, incomingMs: 90_000))
        XCTAssertNil(PairTransitionTiming(spec: spec, outgoingMs: 7100, incomingMs: 90_000))
    }

    func testMeasurementsKeepAbsoluteAmplitudeAndOppositePhaseStereoEnergy() throws {
        var accumulator = TransitionSampleAccumulator(bins: 2, frames: 4)
        let left: [Float] = [0.25, 0.25, 0.5, 0.5]
        let right = left.map { -$0 }
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in accumulator.add([l.baseAddress!, r.baseAddress!], count: 4, offset: 0) }
        }
        let result = try XCTUnwrap(accumulator.result(startMs: 0, durationMs: 4, sampleRate: 1000, channels: 2))
        XCTAssertEqual(result.peaks, [0.25, 0.5])
        XCTAssertEqual(result.rms, [0.25, 0.5])
        XCTAssertEqual(result.peak, 0.5)
        XCTAssertEqual(result.meanRMS, Float(sqrt(0.15625)), accuracy: 1e-6)
        XCTAssertEqual(TransitionAudioSlice.dbFS(0), "−∞ dBFS")
    }

    func testDecodesOnlyRequestedAudioWindowAndRefusesTruncatedWindows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<16_000 {
            buffer.floatChannelData![0][index] = index < 8000 ? 0.1 : 0.5
            buffer.floatChannelData![1][index] = -(index < 8000 ? 0.1 : 0.5)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let slice = try XCTUnwrap(TransitionAnalysisStore.decode(url: url, range: 1000..<2000, bins: 4))
        XCTAssertEqual(slice.startMs, 1000, accuracy: 0.01)
        XCTAssertEqual(slice.durationMs, 1000, accuracy: 0.01)
        XCTAssertEqual(slice.channels, 2)
        XCTAssertEqual(slice.meanRMS, 0.5, accuracy: 1e-6)
        XCTAssertEqual(slice.peaks, [0.5, 0.5, 0.5, 0.5])
        let detailed = try XCTUnwrap(TransitionAnalysisStore.decode(url: url, range: 1000..<2000, bins: 8192))
        XCTAssertEqual(detailed.peaks.count, 8000)
        XCTAssertTrue(detailed.peaks.allSatisfy { abs($0 - 0.5) < 1e-6 }, "A finer display must not invent empty bins between real samples")
        XCTAssertEqual(detailed.meanRMS, slice.meanRMS, accuracy: 1e-6)
        XCTAssertNil(TransitionAnalysisStore.decode(url: url, range: 1500..<2500))
        XCTAssertNil(TransitionAnalysisStore.decode(url: url, range: 0..<21_000))
    }

    func testSmartBlendAutoMixSmoothsOverlapCurvesAndPreservesCustomEdits() {
        let stockBlend = TransitionSpec.preset(.blend, base: TransitionSpec(durationMs: 4_000))
        let smoothed = SmartBlendAutoMix.smoothedSpec(from: stockBlend)
        XCTAssertEqual(smoothed.preset, .blend)
        XCTAssertTrue(smoothed.bassSwap)
        XCTAssertEqual(smoothed.filter, .highPassInOut)
        // Smooth DJ S-curve enters gradually instead of jumping to 1.0 at t = 0.03
        XCTAssertLessThan(smoothed.gain(.incoming, 0.03), 0.15)
        XCTAssertEqual(smoothed.gain(.incoming, 0.32), 0.80, accuracy: 0.01)
        XCTAssertEqual(smoothed.gain(.outgoing, 0.68), 0.80, accuracy: 0.01)
        XCTAssertTrue(SmartBlendAutoMix.isAutomaticBlend(smoothed))

        // Hand-edited custom curves in Transition Studio must remain untouched
        let handEdited = TransitionEditing.movePoint(stockBlend, .incoming, index: 1, t: 0.25, gain: 0.42)
        XCTAssertFalse(SmartBlendAutoMix.isAutomaticBlend(handEdited))
        XCTAssertEqual(SmartBlendAutoMix.smoothedSpec(from: handEdited), handEdited)
    }

    func testSmartBlendAutoMixTrimsOutroTailSilenceAndSkipsIntroSilence() {
        // Outgoing 15 s slice (300 bins of 50 ms): active musical body for 11.5 s (230 bins), then 3.5 s of quiet tail
        var outRms = [Float](repeating: 0.32, count: 300)
        for i in 230..<300 { outRms[i] = 0.003 }
        let outSlice = TransitionAudioSlice(
            peaks: outRms.map { min(1.0, $0 * 1.4) },
            rms: outRms,
            startMs: 185_000,
            durationMs: 15_000,
            sampleRate: 44_100,
            channels: 2,
            peak: 0.45,
            meanRMS: 0.25
        )

        // Incoming 8 s slice (320 bins of 25 ms): 1.2 s (48 bins) of dead silence, then strong musical attack
        var inRms = [Float](repeating: 0.30, count: 320)
        for i in 0..<48 { inRms[i] = 0.001 }
        let inSlice = TransitionAudioSlice(
            peaks: inRms.map { min(1.0, $0 * 1.5) },
            rms: inRms,
            startMs: 0,
            durationMs: 8_000,
            sampleRate: 44_100,
            channels: 2,
            peak: 0.45,
            meanRMS: 0.26
        )

        let base = TransitionSpec.preset(.blend, base: TransitionSpec(durationMs: 4_000))
        let result = SmartBlendAutoMix.analyze(
            spec: base,
            outgoingDurationMs: 200_000,
            incomingDurationMs: 180_000,
            outgoingSlice: outSlice,
            incomingSlice: inSlice
        )
        // 3,500 ms tail minus ~250 ms natural decay margin ≈ 3,250 ms cut
        XCTAssertGreaterThanOrEqual(result.outgoingCutMs, 3_000)
        XCTAssertLessThanOrEqual(result.outgoingCutMs, 3_500)
        // 1,200 ms intro silence minus 1 bin pre-attack breath ≈ 1,175 ms start
        XCTAssertGreaterThanOrEqual(result.incomingStartMs, 1_100)
        XCTAssertLessThanOrEqual(result.incomingStartMs, 1_300)

        // Manual cues set in Transition Studio are respected and not overwritten
        var manualCued = base
        manualCued.outgoingCutMs = 1_500
        manualCued.incomingStartMs = 500
        let preserved = SmartBlendAutoMix.analyze(
            spec: manualCued,
            outgoingDurationMs: 200_000,
            incomingDurationMs: 180_000,
            outgoingSlice: outSlice,
            incomingSlice: inSlice
        )
        XCTAssertEqual(preserved.outgoingCutMs, 1_500)
        XCTAssertEqual(preserved.incomingStartMs, 500)
    }

    func testSmartBlendAutoMixQuantizesDurationToBeatPhraseWhenTemposMatch() {
        // 120 BPM = 500 ms per beat -> 10 bins per beat at 50 ms/bin
        var outRms = [Float](repeating: 0.18, count: 300)
        for i in stride(from: 0, to: 300, by: 10) { outRms[i] = 0.55 }
        let outSlice = TransitionAudioSlice(
            peaks: outRms.map { min(1.0, $0 * 1.3) },
            rms: outRms,
            startMs: 185_000,
            durationMs: 15_000,
            sampleRate: 44_100,
            channels: 2,
            peak: 0.72,
            meanRMS: 0.24
        )

        // Incoming 120 BPM = 500 ms per beat -> 20 bins per beat at 25 ms/bin, with phase offset +150 ms (6 bins)
        var inRms = [Float](repeating: 0.18, count: 320)
        for i in stride(from: 6, to: 320, by: 20) { inRms[i] = 0.55 }
        let inSlice = TransitionAudioSlice(
            peaks: inRms.map { min(1.0, $0 * 1.3) },
            rms: inRms,
            startMs: 0,
            durationMs: 8_000,
            sampleRate: 44_100,
            channels: 2,
            peak: 0.72,
            meanRMS: 0.24
        )

        let base = TransitionSpec.preset(.blend, base: TransitionSpec(durationMs: 4_300))
        let matched = SmartBlendAutoMix.analyze(
            spec: base,
            outgoingDurationMs: 200_000,
            incomingDurationMs: 180_000,
            outgoingSlice: outSlice,
            incomingSlice: inSlice,
            outgoingBpm: 120,
            incomingBpm: 120
        )
        XCTAssertTrue(matched.tempoMatched)
        // 8 beats at 120 BPM (500 ms/beat) = 4,000 ms
        XCTAssertEqual(matched.durationMs, 4_000)
        // Incoming beat phase (+150 ms) is aligned to the outgoing beat grid
        XCTAssertEqual(Double(matched.incomingStartMs), 150.0, accuracy: 30.0)

        // Incompatible tempos (128 BPM vs 92 BPM) do not force tempoMatched
        let mismatched = SmartBlendAutoMix.analyze(
            spec: base,
            outgoingDurationMs: 200_000,
            incomingDurationMs: 180_000,
            outgoingSlice: nil,
            incomingSlice: nil,
            outgoingBpm: 128,
            incomingBpm: 92
        )
        XCTAssertFalse(mismatched.tempoMatched)
    }

    func testShortManualModePreservesSmartBlendPresetAndSmoothCurve() {
        var global = GlobalTransitionSettings()
        global.defaultChoice = .custom(TransitionSpec.preset(.blend, base: TransitionSpec(durationMs: 5_000)))
        global.manualMode = .short
        global.shortManualDurationMs = 800
        let manual = global.manualSpec
        XCTAssertNotNil(manual)
        XCTAssertEqual(manual?.durationMs, 800)
        XCTAssertEqual(manual?.preset, .blend)
        XCTAssertEqual(manual?.bassSwap, true)
        XCTAssertEqual(manual?.filter, .highPassInOut)
        XCTAssertLessThan(manual?.gain(.incoming, 0.03) ?? 1, 0.15)
    }
}

