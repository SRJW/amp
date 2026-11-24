import Foundation
import SwiftUI
import Observation

/// The listener's app preferences (Android's ThemeRepository and friends), saved as JSON.
@MainActor
@Observable
final class AppSettings {
    struct Stored: Codable, Equatable {
        var theme: ThemeChoice = .system
        /// Glass material on floating surfaces, independent of the theme.
        var glassEnabled = true
        var startSection: String = LibrarySection.library.rawValue
        var introductionCompleted = false
        var typeface: AppTypeface = .system
        var boldText = false
        var language: AppLanguage = .system
        var visualizer = VisualizerSettings()
        var playerBackground = PlayerBackgroundSettings()
        /// An imported theme in use instead of [theme], by id.
        var customThemeId: String?
        var importedThemes: [ImportedTheme] = []
        /// Continue playing through All Songs after a song chosen from search finishes.
        var continuousPlayback = false
        /// Pause automatically when wired or Bluetooth headphones disconnect.
        var pauseOnDisconnect = true
        /// Resume automatically from the same position when headphones reconnect after an automatic disconnect pause.
        var resumeOnConnect = false
        /// Bypass DSP/EQ/crossfades and match hardware sample rate (for wired USB-C/Lightning DACs).
        var bitPerfectMode = false
        /// The 5 configurable secondary action buttons on Now Playing.
        var nowPlayingButtons: [NowPlayingActionButton] = NowPlayingActionButton.defaults
        /// Artist IDs starred as favorites from the Artist page.
        var favoriteArtistIds: [Int64] = []

        init() {}

        /// Older files without a field keep its default.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            theme = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? .system
            glassEnabled = try c.decodeIfPresent(Bool.self, forKey: .glassEnabled) ?? true
            startSection = try c.decodeIfPresent(String.self, forKey: .startSection) ?? LibrarySection.library.rawValue
            introductionCompleted = try c.decodeIfPresent(Bool.self, forKey: .introductionCompleted) ?? false
            typeface = (try? c.decodeIfPresent(AppTypeface.self, forKey: .typeface)) ?? .system
            boldText = try c.decodeIfPresent(Bool.self, forKey: .boldText) ?? false
            language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? .system
            visualizer = (try? c.decodeIfPresent(VisualizerSettings.self, forKey: .visualizer)) ?? VisualizerSettings()
            playerBackground = (try? c.decodeIfPresent(PlayerBackgroundSettings.self, forKey: .playerBackground)) ?? PlayerBackgroundSettings()
            customThemeId = try? c.decodeIfPresent(String.self, forKey: .customThemeId)
            importedThemes = (try? c.decodeIfPresent([ImportedTheme].self, forKey: .importedThemes)) ?? []
            continuousPlayback = try c.decodeIfPresent(Bool.self, forKey: .continuousPlayback) ?? false
            pauseOnDisconnect = try c.decodeIfPresent(Bool.self, forKey: .pauseOnDisconnect) ?? true
            resumeOnConnect = try c.decodeIfPresent(Bool.self, forKey: .resumeOnConnect) ?? false
            bitPerfectMode = try c.decodeIfPresent(Bool.self, forKey: .bitPerfectMode) ?? false
            let decodedButtons = (try? c.decodeIfPresent([NowPlayingActionButton].self, forKey: .nowPlayingButtons)) ?? NowPlayingActionButton.defaults
            nowPlayingButtons = NowPlayingActionButton.normalized(decodedButtons)
            favoriteArtistIds = (try? c.decodeIfPresent([Int64].self, forKey: .favoriteArtistIds)) ?? []
        }
    }

    private(set) var stored: Stored
    @ObservationIgnored private let store = JSONStore<Stored>(name: "settings.json")

    init() {
        stored = store.load() ?? Stored()
        AppLocalization.shared.apply(stored.language)
    }

    var language: AppLanguage {
        get { stored.language }
        set {
            update { $0.language = newValue }
            AppLocalization.shared.apply(newValue)
            store.saveNow(stored)
        }
    }

    var theme: ThemeChoice {
        get { stored.theme }
        set { update { $0.theme = newValue } }
    }

    var glassEnabled: Bool {
        get { stored.glassEnabled }
        set { update { $0.glassEnabled = newValue } }
    }

    var startSection: LibrarySection {
        get { .library }
        set { update { $0.startSection = newValue.rawValue } }
    }

    var introductionCompleted: Bool {
        get { stored.introductionCompleted }
        set { update { $0.introductionCompleted = newValue }; store.saveNow(stored) }
    }

    var typeface: AppTypeface {
        get { stored.typeface }
        set { update { $0.typeface = newValue } }
    }

    var boldText: Bool {
        get { stored.boldText }
        set { update { $0.boldText = newValue } }
    }

    var visibleSections: [LibrarySection] { [.library, .equalizer, .search] }

    var visualizer: VisualizerSettings {
        get { stored.visualizer }
        set { update { $0.visualizer = newValue } }
    }

    var playerBackground: PlayerBackgroundSettings {
        get { stored.playerBackground }
        set { update { $0.playerBackground = newValue } }
    }

    var continuousPlayback: Bool {
        get { stored.continuousPlayback }
        set { update { $0.continuousPlayback = newValue } }
    }

    var pauseOnDisconnect: Bool {
        get { stored.pauseOnDisconnect }
        set { update { $0.pauseOnDisconnect = newValue } }
    }

    var resumeOnConnect: Bool {
        get { stored.resumeOnConnect }
        set { update { $0.resumeOnConnect = newValue } }
    }

    var bitPerfectMode: Bool {
        get { stored.bitPerfectMode }
        set { update { $0.bitPerfectMode = newValue } }
    }

    var nowPlayingButtons: [NowPlayingActionButton] {
        get { NowPlayingActionButton.normalized(stored.nowPlayingButtons) }
        set { update { $0.nowPlayingButtons = NowPlayingActionButton.normalized(newValue) } }
    }

    func setNowPlayingButton(_ button: NowPlayingActionButton, at slot: Int) {
        guard (0..<NowPlayingActionButton.slotCount).contains(slot) else { return }
        var updated = nowPlayingButtons
        updated[slot] = button
        nowPlayingButtons = updated
    }

    func isArtistFavorite(_ artistId: Int64) -> Bool {
        stored.favoriteArtistIds.contains(artistId)
    }

    func toggleFavoriteArtist(_ artistId: Int64) {
        update { stored in
            if let index = stored.favoriteArtistIds.firstIndex(of: artistId) {
                stored.favoriteArtistIds.remove(at: index)
            } else {
                stored.favoriteArtistIds.append(artistId)
            }
        }
    }

    /// The imported theme in use, if any.
    var customTheme: ImportedTheme? {
        stored.customThemeId.flatMap { id in stored.importedThemes.first { $0.id == id } }
    }

    var importedThemes: [ImportedTheme] { stored.importedThemes }

    /// The appearance the app asks for: an imported theme's own, else the chosen one.
    var colorScheme: ColorScheme? {
        if let customTheme { return customTheme.isDark ? .dark : .light }
        return theme.colorScheme
    }

    /// Adds (or replaces) a theme and switches to it.
    func importTheme(_ theme: ImportedTheme) {
        update { stored in
            stored.importedThemes.removeAll { $0.id == theme.id }
            stored.importedThemes.append(theme)
            stored.customThemeId = theme.id
        }
    }

    func useCustomTheme(_ id: String?) {
        update { $0.customThemeId = id }
    }

    func deleteTheme(_ id: String) {
        update { stored in
            stored.importedThemes.removeAll { $0.id == id }
            if stored.customThemeId == id { stored.customThemeId = nil }
        }
    }

    func persistNow() {
        store.saveNow(stored)
    }

    private func update(_ change: (inout Stored) -> Void) {
        change(&stored)
        store.save(stored)
    }
}

/// Configurable buttons for the 5-slot secondary action row in Now Playing.
enum NowPlayingActionButton: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case favorite
    case share
    case more
    case shuffle
    case repeatMode
    case lyrics
    case queue
    case addToPlaylist
    case visualizer
    case bookmarks
    case musicInfo
    case goToAlbum
    case goToArtist
    case audioOutput
    case eqToggle
    case sleepTimer

    var id: String { rawValue }
    static let slotCount = 5
    static let defaults: [Self] = [.favorite, .share, .more, .shuffle, .repeatMode]

    static func normalized(_ list: [Self]) -> [Self] {
        var result = Array(list.prefix(slotCount))
        while result.count < slotCount {
            result.append(defaults[result.count])
        }
        return result
    }

    var label: String {
        switch self {
        case .favorite: "Favorite"
        case .share: "Share"
        case .more: "More options"
        case .shuffle: "Shuffle"
        case .repeatMode: "Repeat"
        case .lyrics: "Lyrics"
        case .queue: "Queue"
        case .addToPlaylist: "Add to playlist"
        case .visualizer: "Visualizer"
        case .bookmarks: "Bookmarks & A–B loop"
        case .musicInfo: "Music information"
        case .goToAlbum: "Go to album"
        case .goToArtist: "Go to artist"
        case .audioOutput: "Audio output"
        case .eqToggle: "Equalizer"
        case .sleepTimer: "Sleep timer"
        }
    }

    var systemImage: String {
        switch self {
        case .favorite: "star"
        case .share: "square.and.arrow.up"
        case .more: "ellipsis"
        case .shuffle: "shuffle"
        case .repeatMode: "repeat"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        case .addToPlaylist: "music.note.list"
        case .visualizer: "waveform"
        case .bookmarks: "bookmark.square"
        case .musicInfo: "info.circle"
        case .goToAlbum: "square.stack"
        case .goToArtist: "person"
        case .audioOutput: "airplayaudio"
        case .eqToggle: "slider.vertical.3"
        case .sleepTimer: "moon.zzz"
        }
    }
}
