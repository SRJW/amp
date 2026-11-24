import AVFoundation
import Foundation

/// One output port of the current audio route, as iOS describes it.
struct OutputPort: Equatable {
    /// Port type in plain words ("Bluetooth (A2DP)"); the device's own name is kept out of reports.
    let typeName: String
    let name: String
    let spatialAudio: Bool
}

/// The audio session's output side, as iOS reports it.
struct OutputDiagnostics: Equatable {
    let route: [OutputPort]
    let sampleRateHz: Int?
    let channels: Int?
    let bufferMs: Double?
    let latencyMs: Double?

    var spatialAudio: Bool { route.contains(where: \.spatialAudio) }

    /// What the shared audio session says right now.
    static func current() -> OutputDiagnostics {
        let session = AVAudioSession.sharedInstance()
        let ports = session.currentRoute.outputs.map { port in
            OutputPort(typeName: portTypeName(port.portType), name: port.portName, spatialAudio: port.isSpatialAudioEnabled)
        }
        return OutputDiagnostics(
            route: ports,
            sampleRateHz: session.sampleRate > 0 ? Int(session.sampleRate) : nil,
            channels: session.outputNumberOfChannels > 0 ? session.outputNumberOfChannels : nil,
            bufferMs: session.ioBufferDuration > 0 ? session.ioBufferDuration * 1000 : nil,
            latencyMs: session.outputLatency > 0 ? session.outputLatency * 1000 : nil
        )
    }

    static func portTypeName(_ type: AVAudioSession.Port) -> String {
        switch type {
        case .builtInSpeaker: "Speaker"
        case .builtInReceiver: "Receiver"
        case .headphones: "Wired headphones"
        case .bluetoothA2DP: "Bluetooth (A2DP)"
        case .bluetoothLE: "Bluetooth LE"
        case .bluetoothHFP: "Bluetooth (hands-free)"
        case .airPlay: "AirPlay"
        case .usbAudio: "USB audio"
        case .HDMI: "HDMI"
        case .carAudio: "CarPlay"
        case .lineOut: "Line out"
        default: type.rawValue
        }
    }
}

/// "32-bit float, 48 kHz, 2 (Stereo)" for a PCM format the engine uses.
func pcmFormatText(_ format: AVAudioFormat?) -> String? {
    guard let format, format.sampleRate > 0 else { return nil }
    let encoding: String? = switch format.commonFormat {
    case .pcmFormatFloat32: "32-bit float"
    case .pcmFormatFloat64: "64-bit float"
    case .pcmFormatInt16: "16-bit integer"
    case .pcmFormatInt32: "32-bit integer"
    default: nil
    }
    let parts = [encoding, MediaFormats.sampleRateText(Int(format.sampleRate)), MediaFormats.channelsText(Int(format.channelCount))]
    return parts.compactMap { $0 }.joined(separator: ", ")
}

/// Honest assessment of whether the current output path is running bit-perfect/direct.
enum BitPerfectStatus: Equatable, Sendable {
    case off
    case idle
    case active(sampleRateHz: Int, port: String)
    case resampled(sourceHz: Int, outputHz: Int, port: String)
    case lossyRoute(port: String)

    static func evaluate(enabled: Bool, sourceRateHz: Int?, output: OutputDiagnostics?) -> BitPerfectStatus {
        guard enabled else { return .off }
        guard let sourceRateHz, sourceRateHz > 0 else { return .idle }
        let ports = output?.route ?? []
        let portLabel = ports.map(\.typeName).joined(separator: ", ")
        let displayPort = portLabel.isEmpty ? "System output" : portLabel
        let isWirelessLossy = ports.contains { port in
            port.typeName.hasPrefix("Bluetooth") || port.typeName == "AirPlay"
        }
        if isWirelessLossy {
            return .lossyRoute(port: displayPort)
        }
        if let outHz = output?.sampleRateHz, outHz > 0 {
            if abs(outHz - sourceRateHz) <= 10 {
                return .active(sampleRateHz: outHz, port: displayPort)
            }
            return .resampled(sourceHz: sourceRateHz, outputHz: outHz, port: displayPort)
        }
        return .idle
    }

    var badge: String {
        switch self {
        case .off: "Off"
        case .idle: "Ready"
        case .active: "Direct"
        case .resampled: "Resampled"
        case .lossyRoute: "Wireless"
        }
    }

    var detail: String {
        switch self {
        case .off:
            "Disabled; EQ and transitions are available"
        case .idle:
            "Enabled; waiting for a track to start"
        case .active(let rateHz, let port):
            "DSP bypassed, unity gain, \(MediaFormats.sampleRateText(rateHz)) matched on \(port)"
        case .resampled(let sourceHz, let outputHz, let port):
            "DSP bypassed, but \(port) runs at \(MediaFormats.sampleRateText(outputHz)) instead of \(MediaFormats.sampleRateText(sourceHz))"
        case .lossyRoute(let port):
            "DSP bypassed, but \(port) re-encodes audio wirelessly (connect a USB-C / Lightning DAC for direct output)"
        }
    }
}

/// Everything the report can include; any part may be missing.
struct DiagnosticsSnapshot {
    var source: SourceDiagnostics?
    /// "playing", "paused", "idle".
    var state: String
    /// The format the playing file is decoded to, before the app's processing.
    var decoderInput: String?
    var decoderName: String = "Core Audio file reader"
    /// The format the app hands to iOS after its processing.
    var sentToSystem: String?
    var eq: EqStage?
    var headroom: HeadroomEstimate?
    var peak: PeakReading?
    var output: OutputDiagnostics?
    /// True while a transition fades between two tracks; nil when not known.
    var transitionFading: Bool?
    var bitPerfect: BitPerfectStatus = .off
}

/// A plain-text summary of the current track's audio path, for the user to copy or share. Built
/// only from the inspector's values; it never contains file paths, library ids or device names
/// (Bluetooth names are often personal), and text values are stripped of control characters and
/// length-limited. Unknown values are written as "unavailable", never as 0.
enum DiagnosticsReport {
    private static let maxText = 120
    private static let unavailable = "unavailable"

    static func build(_ snapshot: DiagnosticsSnapshot) -> String {
        var out = ReportBuilder()
        out.append("amp audio details")
        out.section("Track")
        if let source = snapshot.source {
            out.line("Title", clean(source.title))
            out.line("Artist", clean(source.artist))
            out.line("Album", clean(source.album))
            out.section("Source file")
            out.line("Container", fact(source.container))
            out.line("Codec", fact(source.codec))
            out.line("Sample rate", fact(source.sampleRate))
            out.line("Channels", fact(source.channels))
            out.line("Bit depth", source.bitDepth.map { factText($0) } ?? source.bitDepthNote.map { clean($0) } ?? unavailable)
            out.line("Bitrate", fact(source.bitrate))
            out.line("Duration", fact(source.duration))
            out.line("File size", fact(source.fileSize))
            if let problem = source.problem { out.line("Note", clean(problem)) }
        } else {
            out.line("Track", unavailable)
        }

        out.section("Playback (reported by the player)")
        out.line("State", snapshot.state)
        out.line("Decoder", snapshot.decoderName)
        out.line("Decoder output", snapshot.decoderInput ?? unavailable)
        out.line("Sent to iOS audio", snapshot.sentToSystem ?? unavailable)

        out.section("App processing")
        out.line("Bit-Perfect mode", "\(snapshot.bitPerfect.badge): \(snapshot.bitPerfect.detail)")
        let fade: String = switch snapshot.transitionFading {
        case true?: "fading between two tracks (Transition Studio)"
        case false?: "unity gain (no change)"
        case nil: unavailable
        }
        out.line("Transition", fade)
        if let eq = snapshot.eq {
            out.line("Equalizer", "\(eq.status.rawValue): \(clean(eq.reason))")
            if eq.status == .active {
                for (i, band) in eq.activeBands.enumerated() {
                    let skipped = band.skippedAtThisSampleRate ? " (skipped at this sample rate)" : ""
                    let text = String(format: "%.0f Hz %+.1f dB Q %.2f %@%@", band.frequencyHz, band.gainDb, band.q,
                                      band.type.rawValue.lowercased(), skipped)
                    out.line("  Band \(i + 1)", text)
                }
            }
        } else {
            out.line("Equalizer", unavailable)
        }
        out.line("Preamp, bass boost, virtualizer, loudness, limiter", "not part of this app version")
        if let headroom = snapshot.headroom {
            out.line("Clipping risk (estimate)", String(format: "%@, max EQ boost %+.1f dB", headroom.risk.rawValue, headroom.maxBoostDb))
        }
        if let peak = snapshot.peak, peak.frames > 0 {
            let db = peak.peakDbfs.map { String(format: "%.1f", $0) } ?? unavailable
            out.line("Measured sample peak (after EQ)",
                     String(format: "%@ dBFS over %.0f s, %lld samples at full scale", db, peak.secondsMeasured, peak.fullScaleSamples))
        }

        out.section("Output (reported by iOS)")
        if let output = snapshot.output {
            let route = output.route.map(\.typeName).joined(separator: ", ")
            out.line("Route", route.isEmpty ? unavailable : route)
            out.line("Session sample rate", output.sampleRateHz.map(MediaFormats.sampleRateText) ?? unavailable)
            out.line("Output channels", output.channels.map(MediaFormats.channelsText) ?? unavailable)
            out.line("Output latency", output.latencyMs.map { String(format: "%.0f ms", $0) } ?? unavailable)
            out.line("Spatial audio", output.spatialAudio ? "on" : "off")
        } else {
            out.line("Route", unavailable)
        }
        out.section("Limits")
        out.append("- iOS mixes, may resample and may process audio after the app (and Bluetooth re-encodes); that part is not visible to the app.")
        out.append("- Peaks are sample peaks measured after the EQ; peaks between samples are not measured.")
        return out.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fact(_ value: Fact?) -> String {
        value.map { factText($0) } ?? unavailable
    }

    private static func factText(_ value: Fact) -> String { "\(clean(value.value)) (\(value.provenance.rawValue))" }

    /// No control characters or line breaks, and a sane length.
    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(scalars.trimmingCharacters(in: .whitespaces).prefix(maxText))
    }
}

private struct ReportBuilder {
    var text = ""

    mutating func append(_ line: String) { text += line + "\n" }

    mutating func section(_ title: String) {
        text += "\n[\(title)]\n"
    }

    mutating func line(_ label: String, _ value: String) { append("\(label): \(value)") }
}
