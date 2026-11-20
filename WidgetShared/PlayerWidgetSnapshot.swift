import Foundation

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
    static let empty = Self(title: "amp", artist: "Open your music", isPlaying: false, songID: nil, hasArtwork: false)
    // Persisted by WidgetKit; retain the identifier for widgets already on the Home Screen.
    static let kind = "ErhuPlayerWidget"
    static let controlKind = "com.erhu.player.open" // Preserve already installed Control Center tiles.
    static var folder: URL? {
        PlayerWidgetStorage.shared?.folder
    }
    /// A temporary image-cache eviction must not erase a valid shared cover for this track.
    func retainingArtwork(from previous: Self?, available: (String) -> Bool) -> Self {
        guard !hasArtwork, let previous, previous.songID == songID, songID != nil,
              previous.hasArtwork, let filename = previous.artworkFileName, available(filename) else { return self }
        var result = self
        result.hasArtwork = true
        result.artworkFileName = filename
        return result
    }
    func samePlaybackState(as other: Self?) -> Bool {
        guard let other else { return false }
        return songID == other.songID && title == other.title && artist == other.artist && album == other.album
            && isPlaying == other.isPlaying && hasArtwork == other.hasArtwork && artworkFileName == other.artworkFileName
            && durationMs == other.durationMs
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
