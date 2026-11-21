import Foundation

enum PlaybackVisualPosition {
    /// Never let a stalled render clock run a visual playhead beyond the next buffer.
    static let maximumInterpolation = 0.1
    static func interpolated(_ position: Int64, elapsed: Double, duration: Int64) -> Int64 {
        let delta = elapsed.isFinite ? min(max(elapsed, 0), maximumInterpolation) : 0
        return min(max(position + Int64(delta * 1000), 0), max(duration, 0))
    }
}

/// A display clock advances every frame even when the audio render clock publishes in buffers.
/// Small timing differences are corrected gradually; explicit seeks reset it immediately.
struct PlaybackDisplayTimeline {
    static let correctionSeconds = 0.35
    private var entryID: UUID?
    private var lastUptime: Double?
    private var displayedMs = 0.0

    mutating func reset() { entryID = nil; lastUptime = nil }

    mutating func position(audioMs: Int64, entry: UUID, uptime: Double, durationMs: Int64, playing: Bool) -> Int64 {
        let audio = Double(min(max(audioMs, 0), max(durationMs, 0)))
        guard playing, uptime.isFinite, entryID == entry, let previousUptime = lastUptime,
              uptime >= previousUptime else {
            entryID = playing ? entry : nil
            lastUptime = uptime.isFinite ? uptime : nil
            displayedMs = audio
            return Int64(audio)
        }
        let elapsed = uptime - previousUptime
        let predicted = displayedMs + elapsed * 1000
        let correction = min(elapsed / Self.correctionSeconds, 1)
        let corrected = predicted + (audio - predicted) * correction
        // Do not move backwards to chase a late buffer. A long gap means the view was suspended.
        displayedMs = min(max(elapsed >= Self.correctionSeconds ? audio : max(displayedMs, corrected), 0), Double(max(durationMs, 0)))
        lastUptime = uptime
        return Int64(displayedMs.rounded())
    }
}

enum PlayerWaveformMode: String, CaseIterable, Identifiable {
    case fullTrack, scrolling
    var id: String { rawValue }
    var label: String { self == .fullTrack ? "Static · full song" : "Scrolling · follows playback" }
}

enum PlaybackPreferences {
    static let waveformKey = "amp.player.waveformMode"
    static let defaultWaveform = PlayerWaveformMode.scrolling.rawValue
    static let crossfadeRange = 1.0...12.0
    static let crossfadeStep = 1.0
    static let seekSize: Double = 0.075
    static let skipSize: Double = 0.105
    static let playSize: Double = 0.15
    static let playingSize: Double = 0.12
    static let pressedScale = 0.85

    /// A manual handover must fit in the audio left on both decks.
    static func handoffDuration(requested: Int, outgoingRemaining: Int64, incomingRemaining: Int64) -> Int {
        max(1, min(max(requested, 20), Int(max(1, outgoingRemaining)), Int(max(1, incomingRemaining))))
    }
}

/// In static mode the same screen coordinate always represents the same time in the file.
struct FullTrackWaveformGeometry {
    let durationMs: Int64
    let width: Double
    func position(at x: Double) -> Int64 {
        guard width.isFinite, width > 0, x.isFinite, durationMs > 0 else { return 0 }
        return Int64((min(max(x / width, 0), 1) * Double(durationMs)).rounded())
    }
}
