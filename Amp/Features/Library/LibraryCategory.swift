import SwiftUI

enum LibraryCategory: String, CaseIterable, Identifiable {
    case songs, albums, artists, playlists, mostPlayed, recentlyPlayed, recentlyAdded, favorites, folders, albumArtists, radio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .songs: "All Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .favorites: "Favorites"
        case .folders: "Folders"
        case .albumArtists: "Album Artists"
        case .radio: "Radio"
        }
    }
    var icon: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists, .albumArtists: "person.2"
        case .playlists: "music.note.list"
        case .mostPlayed: "chart.bar"
        case .recentlyPlayed: "clock"
        case .recentlyAdded: "calendar.badge.plus"
        case .favorites: "heart"
        case .folders: "folder"
        case .radio: "dot.radiowaves.left.and.right"
        }
    }
    var defaultSort: LibrarySort {
        switch self {
        case .mostPlayed: .mostPlayed
        case .recentlyPlayed: .recentlyPlayed
        case .recentlyAdded: .recentlyAdded
        default: .title
        }
    }
    static func ordered(_ stored: String) -> [Self] {
        var result: [Self] = []
        for raw in stored.split(separator: ",") {
            if let item = Self(rawValue: String(raw)), !result.contains(item) { result.append(item) }
        }
        return result + allCases.filter { !result.contains($0) }
    }

    static func hidden(_ stored: String) -> Set<Self> {
        Set(stored.split(separator: ",").compactMap { Self(rawValue: String($0)) })
    }

    static func visible(order: String, hidden: String) -> [Self] {
        let excluded = Self.hidden(hidden)
        return ordered(order).filter { !excluded.contains($0) }
    }
}

enum LibraryCustomizationText {
    static let action = "Customize Library"
    static let instructions = "Drag to reorder. Tap the eye to show or hide a section."
    static let hide = "Hide"
    static let show = "Show"
    static let visible = "Visible"
    static let hidden = "Hidden"
    static let empty = "All sections are hidden. Choose which sections appear in Library."
}

/// One action arrangement for all library categories and search.
struct CategoryHeader<Options: View>: View {
    let title: String
    let icon: String
    let count: Int
    let selecting: Bool
    let shuffle: () -> Void
    let play: () -> Void
    let search: () -> Void
    let select: () -> Void
    @ViewBuilder let options: () -> Options
    var showsTitle = true
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if showsTitle {
                Label(L(title), systemImage: icon).font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("sectionBrowseTitle")
                Text(countLabel(count, "song")).font(.subheadline).foregroundStyle(.secondary)
            }
            GlassGroup(spacing: Spacing.xs, enabled: settings.glassEnabled) {
                HStack(spacing: Spacing.xs) {
                    action(L("Shuffle"), icon: "shuffle", id: "songsShuffle", action: shuffle).disabled(count == 0 || selecting)
                    action(L("Play"), icon: "play.fill", id: "songsPlayAll", action: play).disabled(count == 0 || selecting)
                    action(L("Search"), icon: "magnifyingglass", id: "sectionSearchButton", action: search)
                    action(selecting ? L("Done") : L("Select"), icon: "checklist", id: "songsSelect", action: select)
                    Menu(content: options) {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.onSurface)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassCircle(enabled: settings.glassEnabled, interactive: true)
                    }
                    .menuStyle(.button)
                    .accessibilityLabel(L("More options"))
                }
            }
            .buttonStyle(FloatingControlPressStyle())
        }.padding(.horizontal, Spacing.gutter)
    }
    private func action(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        let active = selecting && id == "songsSelect"
        return Button(action: action) {
            Image(systemName: icon).font(.headline.weight(.bold))
                .foregroundStyle(active ? palette.primary : palette.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
                .glassCapsule(enabled: settings.glassEnabled, interactive: true,
                              tint: active ? palette.primary.opacity(0.30) : nil)
        }.accessibilityLabel(title).accessibilityIdentifier(id)
    }
}


enum LibraryCustomizationPreferences {
    static let orderKey = "library.overview.sectionOrder"
    static let hiddenKey = "library.overview.hiddenSections"
    static let defaultOrder = LibraryCategory.allCases.map(\.rawValue).joined(separator: ",")
}
