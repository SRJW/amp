import Foundation

struct WidgetTonePalette: Codable, Equatable, Sendable {
    var cardTop: UInt32
    var surface: UInt32
    var cardBottom: UInt32
    var content: UInt32
    var secondary: UInt32
    var accent: UInt32
    var rim: UInt32
    var buttonFill: UInt32
    var onButtonFill: UInt32
}

struct WidgetArtworkPalette: Codable, Equatable, Sendable {
    var dark: WidgetTonePalette
    var light: WidgetTonePalette
    var bleed: UInt32
    var bleedDeep: UInt32

    static let fallback = WidgetArtworkPalette(
        dark: WidgetTonePalette(
            cardTop: 0xFF28_2C34, surface: 0xFF1A_1D24, cardBottom: 0xFF0E_1014,
            content: 0xFFF7_F3F2, secondary: 0xFFB0_B3BA, accent: 0xFFF8_F9FA,
            rim: 0xFF5C_6370, buttonFill: 0xFF34_3A46, onButtonFill: 0xFFF7_F3F2
        ),
        light: WidgetTonePalette(
            cardTop: 0xFFF4_F5F8, surface: 0xFFEB_EDF2, cardBottom: 0xFFD6_DAE2,
            content: 0xFF17_141A, secondary: 0xFF53_565E, accent: 0xFF12_1316,
            rim: 0xFF8C_93A0, buttonFill: 0xFFD4_D8E0, onButtonFill: 0xFF17_141A
        ),
        bleed: 0xFF22_262E,
        bleedDeep: 0xFF0F_1116
    )
}

struct PlayerWidgetSnapshot: Codable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var songID: Int64?
    var hasArtwork: Bool
    var artworkFileName: String? = nil
    var album: String? = nil
    var durationMs: Int64? = nil
    var positionMs: Int64? = nil
    var updatedAt: Date? = nil
    var formatBadge: String? = nil
    var waveform: [UInt8]? = nil
    var palette: WidgetArtworkPalette? = nil
    static let empty = Self(title: "amp", artist: "Open your music", isPlaying: false, songID: nil, hasArtwork: false)
    // Persisted by WidgetKit; retain the identifier for widgets already on the Home Screen.
    static let kind = "ErhuPlayerWidget"
    static let compactKind = "com.amp.widget.compact"
    static let immersiveKind = "com.amp.widget.immersive"
    static let playbackKinds = [kind, compactKind, immersiveKind]
    static let controlKind = "com.erhu.player.open" // Preserve already installed Control Center tiles.
    static var folder: URL? {
        PlayerWidgetStorage.shared?.folder
    }
    /// Reduces cached full-track waveform bytes (0..255) into a compact bar envelope for widgets.
    static func downsampleWaveform(_ raw: Data, bars: Int = 30) -> [UInt8]? {
        guard !raw.isEmpty, bars > 0 else { return nil }
        let bytes = [UInt8](raw)
        let count = bytes.count
        var result: [UInt8] = []
        result.reserveCapacity(bars)
        for index in 0..<bars {
            let start = index * count / bars
            let end = min(max(start + 1, (index + 1) * count / bars), count)
            var sum = 0
            for offset in start..<end { sum += Int(bytes[offset]) }
            let average = sum / max(end - start, 1)
            result.append(UInt8(min(max(average, 0), 255)))
        }
        return result
    }
    /// A temporary image-cache eviction must not erase a valid shared cover for this track.
    func retainingArtwork(from previous: Self?, available: (String) -> Bool) -> Self {
        guard let previous, previous.songID == songID, songID != nil else { return self }
        var result = self
        if !result.hasArtwork, previous.hasArtwork, let filename = previous.artworkFileName, available(filename) {
            result.hasArtwork = true
            result.artworkFileName = filename
            if result.palette == nil { result.palette = previous.palette }
        } else if result.hasArtwork, result.palette == nil {
            result.palette = previous.palette
        }
        if result.waveform == nil { result.waveform = previous.waveform }
        return result
    }
    func samePlaybackState(as other: Self?) -> Bool {
        guard let other else { return false }
        return songID == other.songID && title == other.title && artist == other.artist && album == other.album
            && isPlaying == other.isPlaying && hasArtwork == other.hasArtwork && artworkFileName == other.artworkFileName
            && durationMs == other.durationMs && formatBadge == other.formatBadge
            && waveform == other.waveform && palette == other.palette
    }
    static func load() -> Self {
        guard let folder else {
            return Self(title: "Widget unavailable", artist: "Check widget status in amp Settings", isPlaying: false, songID: nil, hasArtwork: false)
        }
        return read(in: folder) ?? .empty
    }
    static func read(in folder: URL) -> Self? {
        for name in ["player.json", "player-last-good.json"] {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
               let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        }
        return nil
    }
}
