import Foundation

/// Live state of an active or imminent Smart Blend (Apple Music AutoMix–style) transition.
struct SmartBlendStatus: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case preparing
        case mixing
    }

    let phase: Phase
    let tempoMatched: Bool
    let durationMs: Int
    let outgoingCutMs: Int
    let incomingStartMs: Int

    @MainActor
    var badgeText: String {
        switch phase {
        case .preparing:
            return tempoMatched ? L("Smart Blend · Tempo Sync") : L("Smart Blend · Ready")
        case .mixing:
            return tempoMatched ? L("Smart Blend · Tempo Sync") : L("Smart Blend · Mixing")
        }
    }
}

/// Intelligent boundary analyzer and curve shaper for `TransitionPreset.blend` (Smart Blend),
/// bringing Apple Music AutoMix–style outro/intro silence trimming, beat-grid phase alignment,
/// bar-quantized transition duration, and smooth DJ S-curve envelopes to on-device playback.
enum SmartBlendAutoMix {
    /// Smooth DJ S-curve for the outgoing track: holds full body through the first half while the
    /// incoming track filters in, swaps bass at t = 0.5, and glides smoothly to silence.
    static let smoothOutgoingCurve = VolumeCurve.of(
        (0.00, 1.00),
        (0.48, 0.96),
        (0.68, 0.80),
        (0.86, 0.36),
        (1.00, 0.00)
    )

    /// Smooth DJ S-curve for the incoming track: rises warmly over the first half while high-passed,
    /// reaching full body right as the center bass swap hands over the low frequencies.
    static let smoothIncomingCurve = VolumeCurve.of(
        (0.00, 0.00),
        (0.14, 0.36),
        (0.32, 0.80),
        (0.52, 0.96),
        (1.00, 1.00)
    )

    struct PulseEstimate: Equatable, Sendable {
        let periodMs: Double
        let phaseMs: Double
        let confidence: Double
    }

    struct AnalysisResult: Equatable, Sendable {
        let spec: TransitionSpec
        let tempoMatched: Bool
        let estimatedBeatPeriodMs: Double?
        let outgoingCutMs: Int
        let incomingStartMs: Int
        let durationMs: Int
    }

    /// True when `spec` uses the automatic Smart Blend preset without custom user-drawn volume curves.
    static func isAutomaticBlend(_ spec: TransitionSpec) -> Bool {
        guard spec.preset == .blend else { return false }
        if VolumeShape.of(spec) == .overlap { return true }
        return spec.curve == .custom
            && spec.outgoingCurve == smoothOutgoingCurve
            && spec.incomingCurve == smoothIncomingCurve
    }

    /// Replaces the abrupt 3% overlap ramp on a stock `.blend` preset with the smooth AutoMix DJ envelope.
    static func smoothedSpec(from spec: TransitionSpec) -> TransitionSpec {
        guard isAutomaticBlend(spec) else { return spec }
        var out = spec
        out.curve = .custom
        out.outgoingCurve = smoothOutgoingCurve
        out.incomingCurve = smoothIncomingCurve
        return out
    }

    /// Pure, deterministic AutoMix analyzer operating on pre-decoded boundary slices and optional BPM tags.
    static func analyze(
        spec: TransitionSpec,
        outgoingDurationMs: Int64,
        incomingDurationMs: Int64,
        outgoingSlice: TransitionAudioSlice?,
        incomingSlice: TransitionAudioSlice?,
        outgoingBpm: Int? = nil,
        incomingBpm: Int? = nil
    ) -> AnalysisResult {
        var refined = smoothedSpec(from: spec)
        guard spec.preset == .blend, outgoingDurationMs > 2_000, incomingDurationMs > 2_000 else {
            return AnalysisResult(
                spec: refined,
                tempoMatched: false,
                estimatedBeatPeriodMs: nil,
                outgoingCutMs: refined.outgoingCutMs,
                incomingStartMs: refined.incomingStartMs,
                durationMs: refined.durationMs
            )
        }

        // 1. Smart Auto-Cue: trim quiet fade-out tails / dead air on the outgoing track
        if spec.outgoingCutMs == 0, let outgoingSlice {
            let autoCut = detectOutgoingCutMs(slice: outgoingSlice, trackDurationMs: outgoingDurationMs)
            if autoCut >= 200 {
                refined.outgoingCutMs = autoCut
            }
        }

        // 2. Smart Auto-Cue: skip leading dead air / silence before the first musical onset on the incoming track
        if spec.incomingStartMs == 0, let incomingSlice {
            let autoStart = detectIncomingStartMs(slice: incomingSlice, trackDurationMs: incomingDurationMs)
            if autoStart >= 120 {
                refined.incomingStartMs = autoStart
            }
        }

        // 3. Beat-Grid & Tempo Analysis: bar-quantized duration + beat-phase alignment
        let outPulse = detectPulse(
            slice: outgoingSlice,
            activeEndMs: Double(outgoingDurationMs - Int64(refined.outgoingCutMs)),
            isOutgoing: true,
            hintBpm: outgoingBpm
        )
        let inPulse = detectPulse(
            slice: incomingSlice,
            activeStartMs: Double(refined.incomingStartMs),
            isOutgoing: false,
            hintBpm: incomingBpm
        )

        var tempoMatched = false
        var sharedBeatMs: Double?

        if let outPulse, let inPulse,
           let matchedPeriod = compatibleBeatPeriodMs(outgoing: outPulse, incoming: inPulse) {
            tempoMatched = true
            sharedBeatMs = matchedPeriod

            // Quantize transition duration to the nearest musical phrase (4, 8, 12, 16, or 24 beats)
            let quantized = quantizeDurationMs(
                requestedMs: spec.durationMs,
                beatPeriodMs: matchedPeriod,
                outgoingPlayedMs: max(outgoingDurationMs - Int64(refined.outgoingCutMs), 0),
                incomingPlayedMs: max(incomingDurationMs - Int64(refined.incomingStartMs), 0)
            )
            refined.durationMs = quantized

            // Micro-align incomingStartMs so the incoming beat grid lands in phase with the outgoing beat grid
            if spec.incomingStartMs == 0, let outgoingSlice, let incomingSlice {
                let effectiveDuration = refined.effectiveDurationMs(
                    outgoingDurationMs: outgoingDurationMs,
                    incomingDurationMs: incomingDurationMs
                )
                let startAtMs = Double(refined.outgoingEndMs(outgoingDurationMs) - Int64(effectiveDuration))
                let alignedStart = alignIncomingBeatPhase(
                    baseIncomingStartMs: refined.incomingStartMs,
                    startAtMs: startAtMs,
                    beatPeriodMs: matchedPeriod,
                    outgoingSlice: outgoingSlice,
                    outgoingPulse: outPulse,
                    incomingSlice: incomingSlice,
                    incomingPulse: inPulse,
                    incomingDurationMs: incomingDurationMs
                )
                refined.incomingStartMs = alignedStart
            }
        } else if let singlePulse = outPulse ?? inPulse, singlePulse.confidence >= 0.32 {
            // Even when only one track has a clear beat grid, quantize the blend duration to an even phrase of that beat
            sharedBeatMs = singlePulse.periodMs
            refined.durationMs = quantizeDurationMs(
                requestedMs: spec.durationMs,
                beatPeriodMs: singlePulse.periodMs,
                outgoingPlayedMs: max(outgoingDurationMs - Int64(refined.outgoingCutMs), 0),
                incomingPlayedMs: max(incomingDurationMs - Int64(refined.incomingStartMs), 0)
            )
        }

        return AnalysisResult(
            spec: refined,
            tempoMatched: tempoMatched,
            estimatedBeatPeriodMs: sharedBeatMs,
            outgoingCutMs: refined.outgoingCutMs,
            incomingStartMs: refined.incomingStartMs,
            durationMs: refined.durationMs
        )
    }

    // MARK: - Auto-Cue Detection

    /// Finds how many milliseconds of quiet fade-out or silence at the end of `slice` should be trimmed
    /// so the transition starts while the outgoing song still has musical energy.
    static func detectOutgoingCutMs(slice: TransitionAudioSlice, trackDurationMs: Int64) -> Int {
        let count = slice.rms.count
        guard count >= 8, slice.durationMs > 500 else { return 0 }
        let binMs = slice.durationMs / Double(count)

        // Estimate active body level from the earlier 65% of the window
        let bodyEnd = max(1, Int((Double(count) * 0.65).rounded()))
        let bodySamples = Array(slice.rms[0..<bodyEnd]).filter { $0 > 0.002 }.sorted()
        guard !bodySamples.isEmpty else { return 0 }
        let bodyRef = bodySamples[min(bodySamples.count - 1, Int(Double(bodySamples.count) * 0.72))]
        guard bodyRef >= 0.012 else { return 0 }

        // Threshold where the musical body has faded into a quiet tail (~ -36 dBFS or 16% of active body)
        let threshold = max(Float(0.014), min(Float(0.085), bodyRef * 0.16))

        var lastActiveBin = count - 1
        while lastActiveBin > 0 {
            let current = slice.rms[lastActiveBin]
            let prev = slice.rms[max(0, lastActiveBin - 1)]
            if current >= threshold && (prev >= threshold * 0.8 || count < 16) {
                break
            }
            lastActiveBin -= 1
        }

        // Leave ~250 ms of natural decay after the last energetic frame
        let rawCutMs = Double(count - 1 - lastActiveBin) * binMs - 250.0
        guard rawCutMs >= 200 else { return 0 }

        let maxAllowedCut = min(10_000, Int(trackDurationMs / 3))
        return Int(rawCutMs.rounded()).clamped(0, max(0, maxAllowedCut))
    }

    /// Finds how many milliseconds of leading silence or low noise at the start of `slice` should be skipped
    /// so the incoming track enters right on its first musical attack.
    static func detectIncomingStartMs(slice: TransitionAudioSlice, trackDurationMs: Int64) -> Int {
        let count = slice.rms.count
        guard count >= 8, slice.durationMs > 400 else { return 0 }
        let binMs = slice.durationMs / Double(count)

        let activeSamples = slice.rms.filter { $0 > 0.002 }.sorted()
        guard !activeSamples.isEmpty else { return 0 }
        let activeRef = activeSamples[min(activeSamples.count - 1, Int(Double(activeSamples.count) * 0.78))]
        guard activeRef >= 0.012 else { return 0 }

        let rmsThreshold = max(Float(0.012), min(Float(0.065), activeRef * 0.12))
        let peakThreshold = rmsThreshold * 2.1

        var firstOnsetBin = 0
        var found = false
        for i in 0..<count {
            let rmsOk = slice.rms[i] >= rmsThreshold
            let peakOk = i < slice.peaks.count && slice.peaks[i] >= peakThreshold
            if rmsOk || peakOk {
                firstOnsetBin = i
                found = true
                break
            }
        }
        guard found, firstOnsetBin > 0 else { return 0 }

        // Keep 1 bin (~25-40 ms) of pre-onset breath so the initial transient is never clipped
        let safeBin = max(0, firstOnsetBin - 1)
        let rawStartMs = Double(safeBin) * binMs
        guard rawStartMs >= 120 else { return 0 }

        let maxAllowedStart = min(5_000, Int(trackDurationMs / 4))
        return Int(rawStartMs.rounded()).clamped(0, max(0, maxAllowedStart))
    }

    // MARK: - Beat Grid & Tempo Estimation

    /// Folds any BPM into the fundamental [68, 175] BPM DJ mixing octave.
    static func foldedBeatPeriodMs(forBpm bpm: Int?) -> Double? {
        guard let bpm, (40...260).contains(bpm) else { return nil }
        var folded = Double(bpm)
        while folded < 68 { folded *= 2 }
        while folded > 175 { folded *= 0.5 }
        return 60_000.0 / folded
    }

    /// Estimates local beat period (ms), beat phase offset (ms from `slice.startMs`), and confidence
    /// from the onset flux envelope of a boundary audio slice and optional tag BPM.
    static func detectPulse(
        slice: TransitionAudioSlice?,
        activeStartMs: Double? = nil,
        activeEndMs: Double? = nil,
        isOutgoing: Bool,
        hintBpm: Int?
    ) -> PulseEstimate? {
        let hintPeriod = foldedBeatPeriodMs(forBpm: hintBpm)
        guard let slice, slice.rms.count >= 24, slice.durationMs >= 1_500 else {
            if let hintPeriod {
                return PulseEstimate(periodMs: hintPeriod, phaseMs: 0, confidence: 0.45)
            }
            return nil
        }

        let count = slice.rms.count
        let binMs = slice.durationMs / Double(count)
        guard binMs > 5, binMs <= 120 else {
            if let hintPeriod {
                return PulseEstimate(periodMs: hintPeriod, phaseMs: 0, confidence: 0.45)
            }
            return nil
        }

        let startBin: Int
        if let activeStartMs {
            startBin = Int(((activeStartMs - slice.startMs) / binMs).rounded()).clamped(0, count - 1)
        } else {
            startBin = 0
        }
        let endBin: Int
        if let activeEndMs {
            endBin = Int(((activeEndMs - slice.startMs) / binMs).rounded()).clamped(startBin + 1, count)
        } else {
            endBin = count
        }

        let windowCount = endBin - startBin
        guard windowCount >= 16 else {
            if let hintPeriod {
                return PulseEstimate(periodMs: hintPeriod, phaseMs: 0, confidence: 0.45)
            }
            return nil
        }

        // Half-wave rectified onset flux envelope
        var flux = [Double](repeating: 0, count: windowCount)
        var maxFlux = 0.0
        for i in 1..<windowCount {
            let idx = startBin + i
            let dr = max(0, Double(slice.rms[idx] - slice.rms[idx - 1]))
            let dp: Double
            if idx < slice.peaks.count {
                dp = max(0, Double(slice.peaks[idx] - slice.peaks[idx - 1]))
            } else {
                dp = 0
            }
            let v = dr + 0.35 * dp
            flux[i] = v
            if v > maxFlux { maxFlux = v }
        }

        guard maxFlux > 1e-4 else {
            if let hintPeriod {
                return PulseEstimate(periodMs: hintPeriod, phaseMs: 0, confidence: 0.40)
            }
            return nil
        }
        for i in 0..<windowCount { flux[i] /= maxFlux }

        let minLag = max(2, Int((340.0 / binMs).rounded()))
        let maxLag = min(windowCount / 2, Int((880.0 / binMs).rounded()))
        guard minLag <= maxLag else {
            if let hintPeriod {
                return PulseEstimate(periodMs: hintPeriod, phaseMs: 0, confidence: 0.40)
            }
            return nil
        }

        var energy = 0.0
        for v in flux { energy += v * v }
        guard energy > 1e-6 else { return nil }

        var bestLag = minLag
        var bestScore = -1.0

        for lag in minLag...maxLag {
            var corr = 0.0
            let pairs = windowCount - lag
            guard pairs > 4 else { continue }
            for i in 0..<pairs {
                corr += flux[i] * flux[i + lag]
            }
            var normalized = corr / Double(pairs)
            // Harmonic reinforcement at 2x lag if available
            let doubleLag = lag * 2
            if doubleLag < windowCount - 4 {
                var corr2 = 0.0
                let pairs2 = windowCount - doubleLag
                for i in 0..<pairs2 {
                    corr2 += flux[i] * flux[i + doubleLag]
                }
                normalized += 0.35 * (corr2 / Double(pairs2))
            }
            // Prior boost if close to the track's known BPM tag
            if let hintPeriod {
                let lagMs = Double(lag) * binMs
                let relDiff = abs(lagMs - hintPeriod) / hintPeriod
                if relDiff <= 0.08 {
                    normalized *= 1.35
                }
            }
            if normalized > bestScore {
                bestScore = normalized
                bestLag = lag
            }
        }

        let detectedPeriodMs = Double(bestLag) * binMs
        let periodMs: Double
        if let hintPeriod, abs(detectedPeriodMs - hintPeriod) / hintPeriod <= 0.10 {
            periodMs = hintPeriod
        } else {
            periodMs = hintPeriod ?? detectedPeriodMs
        }

        // Fold onset flux modulo bestLag to find the dominant beat phase relative to slice.startMs
        var phaseBins = [Double](repeating: 0, count: bestLag)
        for i in 0..<windowCount {
            let absoluteBin = startBin + i
            phaseBins[absoluteBin % bestLag] += flux[i]
        }
        var bestPhaseBin = 0
        var bestPhaseVal = -1.0
        for (idx, val) in phaseBins.enumerated() where val > bestPhaseVal {
            bestPhaseVal = val
            bestPhaseBin = idx
        }

        let phaseMs = Double(bestPhaseBin) * binMs
        let rawConfidence = min(1.0, max(0.0, bestScore * 3.2))
        let confidence = hintPeriod != nil ? max(rawConfidence, 0.45) : rawConfidence
        guard confidence >= 0.24 else { return nil }

        return PulseEstimate(periodMs: periodMs, phaseMs: phaseMs, confidence: confidence)
    }

    /// Returns the shared beat period (ms) if `outgoing` and `incoming` have compatible tempos
    /// (within 14% directly, or within 11% of a 2x / 0.5x double/half-time relationship).
    static func compatibleBeatPeriodMs(outgoing: PulseEstimate, incoming: PulseEstimate) -> Double? {
        guard outgoing.confidence >= 0.24, incoming.confidence >= 0.24 else { return nil }
        let pOut = outgoing.periodMs
        let candidates = [incoming.periodMs, incoming.periodMs * 2.0, incoming.periodMs * 0.5]
        for candidate in candidates where (320.0...920.0).contains(candidate) {
            let diff = abs(pOut - candidate) / min(pOut, candidate)
            let tolerance = candidate == incoming.periodMs ? 0.14 : 0.11
            if diff <= tolerance {
                return (pOut + candidate) * 0.5
            }
        }
        return nil
    }

    /// Quantizes the requested transition duration to the nearest musical phrase multiple
    /// (4, 8, 12, 16, or 24 beats) within ±35% of the user's configured duration.
    static func quantizeDurationMs(
        requestedMs: Int,
        beatPeriodMs: Double,
        outgoingPlayedMs: Int64,
        incomingPlayedMs: Int64
    ) -> Int {
        guard beatPeriodMs >= 250, beatPeriodMs <= 1_200 else {
            return TransitionSpec.clampDuration(requestedMs)
        }
        let target = Double(requestedMs)
        let minAllowed = max(Double(TransitionSpec.minDurationMs), target * 0.65)
        let maxTrackHalf = Double(min(outgoingPlayedMs / 2, incomingPlayedMs / 2))
        let maxAllowed = min(Double(TransitionSpec.maxDurationMs), min(target * 1.35, max(minAllowed, maxTrackHalf)))

        let phraseMultiples: [Double] = [2, 4, 8, 12, 16, 24]
        var bestMs = target
        var bestDistance = Double.greatestFiniteMagnitude

        for beats in phraseMultiples {
            let candidate = beats * beatPeriodMs
            guard candidate >= minAllowed, candidate <= maxAllowed else { continue }
            let distance = abs(candidate - target)
            if distance < bestDistance {
                bestDistance = distance
                bestMs = candidate
            }
        }

        return TransitionSpec.clampDuration(Int(bestMs.rounded()))
    }

    /// Micro-adjusts `baseIncomingStartMs` so the incoming beat phase aligns with the outgoing beat grid at `startAtMs`.
    static func alignIncomingBeatPhase(
        baseIncomingStartMs: Int,
        startAtMs: Double,
        beatPeriodMs: Double,
        outgoingSlice: TransitionAudioSlice,
        outgoingPulse: PulseEstimate,
        incomingSlice: TransitionAudioSlice,
        incomingPulse: PulseEstimate,
        incomingDurationMs: Int64
    ) -> Int {
        guard beatPeriodMs >= 250, beatPeriodMs <= 1_000 else { return baseIncomingStartMs }

        let outOffset = startAtMs - outgoingSlice.startMs
        let outNextBeat = positiveMod(outgoingPulse.phaseMs - outOffset, beatPeriodMs)

        let inOffset = Double(baseIncomingStartMs) - incomingSlice.startMs
        let inNextBeat = positiveMod(incomingPulse.phaseMs - inOffset, beatPeriodMs)

        // Advance incomingStartMs by deltaForward so inNextBeat matches outNextBeat
        let deltaForward = positiveMod(inNextBeat - outNextBeat, beatPeriodMs)
        let deltaBackward = beatPeriodMs - deltaForward

        let maxAllowedStart = min(5_000, Int(incomingDurationMs / 4))
        let candidate: Int
        if deltaBackward < deltaForward && baseIncomingStartMs >= Int(deltaBackward.rounded()) {
            candidate = baseIncomingStartMs - Int(deltaBackward.rounded())
        } else if deltaForward <= min(450.0, beatPeriodMs * 0.65) {
            candidate = baseIncomingStartMs + Int(deltaForward.rounded())
        } else {
            candidate = baseIncomingStartMs
        }

        return candidate.clamped(0, max(0, maxAllowedStart))
    }

    private static func positiveMod(_ value: Double, _ modulus: Double) -> Double {
        guard modulus > 0 else { return 0 }
        let rem = value.truncatingRemainder(dividingBy: modulus)
        return rem >= 0 ? rem : rem + modulus
    }
}

/// Asynchronous cache that decodes only the short tail/head boundary windows for Smart Blend pairs.
actor SmartBlendAutoMixStore {
    static let shared = SmartBlendAutoMixStore()

    private struct CacheKey: Hashable {
        let outgoingURL: URL
        let incomingURL: URL
        let outgoingDurationMs: Int64
        let incomingDurationMs: Int64
        let durationMs: Int
        let outgoingCutMs: Int
        let incomingStartMs: Int
    }

    private var cache: [CacheKey: SmartBlendAutoMix.AnalysisResult] = [:]

    /// Outgoing tail window (last 15 s) and incoming head window (first 8 s).
    private static let outgoingWindowMs: Int64 = 15_000
    private static let incomingWindowMs: Int64 = 8_000

    func analyze(
        spec: TransitionSpec,
        outgoing: Song,
        incoming: Song
    ) async -> SmartBlendAutoMix.AnalysisResult {
        let key = CacheKey(
            outgoingURL: outgoing.url,
            incomingURL: incoming.url,
            outgoingDurationMs: outgoing.durationMs,
            incomingDurationMs: incoming.durationMs,
            durationMs: spec.durationMs,
            outgoingCutMs: spec.outgoingCutMs,
            incomingStartMs: spec.incomingStartMs
        )
        if let cached = cache[key] { return cached }

        let outStart = max(0, outgoing.durationMs - Self.outgoingWindowMs)
        let outRange = outStart..<max(outStart, outgoing.durationMs)
        let inEnd = min(incoming.durationMs, Self.incomingWindowMs)
        let inRange = 0..<max(0, inEnd)

        async let outSlice = outRange.count > 500
            ? TransitionAnalysisStore.shared.slice(url: outgoing.url, range: outRange, bins: 300)
            : nil
        async let inSlice = inRange.count > 400
            ? TransitionAnalysisStore.shared.slice(url: incoming.url, range: inRange, bins: 320)
            : nil

        let (resolvedOut, resolvedIn) = await (outSlice, inSlice)
        let result = SmartBlendAutoMix.analyze(
            spec: spec,
            outgoingDurationMs: outgoing.durationMs,
            incomingDurationMs: incoming.durationMs,
            outgoingSlice: resolvedOut,
            incomingSlice: resolvedIn,
            outgoingBpm: outgoing.bpm,
            incomingBpm: incoming.bpm
        )

        if !Task.isCancelled {
            if cache.count >= 16 { cache.removeAll(keepingCapacity: true) }
            cache[key] = result
        }
        return result
    }
}
