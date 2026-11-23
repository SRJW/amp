import AudioToolbox
import AVFoundation
import Foundation
import os

/// The user's equaliser on the audio thread: up to 8 cookbook biquads per channel (Android's
/// CustomEqAudioProcessor). Settings come from the main thread through a lock the audio thread
/// only ever *tries*; if it is busy, the previous coefficients play one more buffer.
final class EqKernel: RenderKernel, @unchecked Sendable {
    struct Parameters: Equatable {
        struct Band: Equatable {
            var gain: Float = 0
            var frequency: Float = 1_000
            var q: Float = Equalizer.defaultQ
            var type: FilterType = .peaking
        }

        var enabled = true
        var b0 = Band(frequency: Equalizer.bandFrequencies[0])
        var b1 = Band(frequency: Equalizer.bandFrequencies[1])
        var b2 = Band(frequency: Equalizer.bandFrequencies[2])
        var b3 = Band(frequency: Equalizer.bandFrequencies[3])
        var b4 = Band(frequency: Equalizer.bandFrequencies[4])
        var b5 = Band(frequency: Equalizer.bandFrequencies[5])
        var b6 = Band(frequency: Equalizer.bandFrequencies[6])
        var b7 = Band(frequency: Equalizer.bandFrequencies[7])
        var activeCount = Equalizer.bandCount

        subscript(_ index: Int) -> Band {
            get {
                switch index {
                case 0: b0; case 1: b1; case 2: b2; case 3: b3
                case 4: b4; case 5: b5; case 6: b6; default: b7
                }
            }
            set {
                switch index {
                case 0: b0 = newValue; case 1: b1 = newValue; case 2: b2 = newValue; case 3: b3 = newValue
                case 4: b4 = newValue; case 5: b5 = newValue; case 6: b6 = newValue; default: b7 = newValue
                }
            }
        }

        var isFlat: Bool {
            for i in 0..<min(activeCount, Equalizer.bandCount) where self[i].gain != 0 { return false }
            return true
        }

        init() {}

        init(_ settings: SoundSettings) {
            enabled = settings.isEqEnabled
            activeCount = settings.activeBandCount.clamped(Equalizer.minBandCount, Equalizer.bandCount)
            for i in 0..<min(settings.bands.count, Equalizer.bandCount) {
                let band = settings.bands[i]
                self[i] = Band(
                    gain: band.gainDb.clamped(Equalizer.minGainDb, Equalizer.maxGainDb),
                    frequency: band.frequencyHz.clamped(Equalizer.minFreqHz, Equalizer.maxFreqHz),
                    q: band.q.clamped(Equalizer.minQ, Equalizer.maxQ),
                    type: band.filterType
                )
            }
        }
    }

    private let pending = OSAllocatedUnfairLock<Parameters?>(initialState: nil)
    private let published = OSAllocatedUnfairLock(initialState: RuntimeState())

    // Audio thread only.
    private var parameters = Parameters()
    private var filters: [[BiquadFilter]] = []
    private var sampleRate = 44_100
    private var channels = 0
    private var needsConfigure = true

    struct RuntimeState: Equatable {
        var configured = false
        var sampleRateHz: Int?
        var channelCount: Int?
    }

    func apply(_ settings: SoundSettings) {
        pending.withLock { $0 = Parameters(settings) }
    }

    /// What the stage is doing now, for the audio inspector.
    func runtimeState(settings: SoundSettings) -> EqRuntimeState {
        let state = published.withLock { $0 }
        let activeCount = settings.activeBandCount.clamped(Equalizer.minBandCount, Equalizer.bandCount)
        return EqRuntimeState(
            enabled: settings.isEqEnabled,
            configured: state.configured,
            sampleRateHz: state.sampleRateHz,
            channelCount: state.channelCount,
            allGainsZero: settings.bands.prefix(activeCount).allSatisfy { $0.gainDb == 0 }
        )
    }

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = Int(sampleRate)
        self.channels = channels
        filters = Array(repeating: Array(repeating: BiquadFilter(), count: Equalizer.bandCount), count: channels)
        needsConfigure = true
        published.withLock { $0 = RuntimeState(configured: true, sampleRateHz: Int(sampleRate), channelCount: channels) }
    }

    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int, timestamp: UnsafePointer<AudioTimeStamp>) {
        if let next = pending.withLockIfAvailable({ value -> Parameters? in
            defer { value = nil }
            return value
        }) ?? nil {
            if next.enabled != parameters.enabled || next.isFlat != parameters.isFlat { resetFilters() }
            parameters = next
            needsConfigure = true
        }
        guard parameters.enabled, !parameters.isFlat, filters.count == buffers.count else { return }
        if needsConfigure { configure() }
        for channel in 0..<buffers.count {
            guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
            filters[channel].withUnsafeMutableBufferPointer { bands in
                for i in 0..<frames {
                    var sample = data[i]
                    for b in 0..<bands.count {
                        sample = bands[b].process(sample)
                    }
                    data[i] = sample.clamped(-1, 1)
                }
            }
        }
    }

    private func configure() {
        needsConfigure = false
        for channel in filters.indices {
            for b in 0..<Equalizer.bandCount {
                let band = parameters[b]
                let usable = b < parameters.activeCount
                    && band.frequency < Float(sampleRate) * Equalizer.maxBandToSampleRateRatio
                filters[channel][b].configure(
                    centerFrequency: band.frequency, sampleRate: sampleRate,
                    gainInDb: usable ? band.gain : 0, q: band.q, type: band.type
                )
            }
        }
    }

    private func resetFilters() {
        for channel in filters.indices {
            for b in filters[channel].indices { filters[channel][b].reset() }
        }
    }

    /// The combined response in dB at each of [frequencies] (for drawing the EQ curve).
    static func response(of settings: SoundSettings, at frequencies: [Float], sampleRate: Int = 44_100) -> [Float] {
        let filters = settings.bands.enumerated().map { index, band -> BiquadFilter in
            var filter = BiquadFilter()
            filter.configure(
                centerFrequency: band.frequencyHz, sampleRate: sampleRate,
                gainInDb: index < settings.activeBandCount ? band.gainDb : 0, q: band.q, type: band.filterType
            )
            return filter
        }
        return frequencies.map { hz in filters.reduce(0) { $0 + $1.frequencyResponse(hz, sampleRate: sampleRate) } }
    }
}
