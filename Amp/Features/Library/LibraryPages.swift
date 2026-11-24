import SwiftUI

struct AlbumsView: View {
    var body: some View { EntityCategoryView(category: .albums) }
}

/// The single library root; migrate the previous saved section order without hiding new categories.
struct LibraryOverviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var themeScheme
    @State private var releases = ReleaseChecker.shared
    @AppStorage(LibraryCustomizationPreferences.orderKey) private var storedOrder = LibraryCustomizationPreferences.defaultOrder
    @AppStorage(LibraryCustomizationPreferences.hiddenKey) private var hiddenSections = ""
    @State private var showsOrder = false
    @State private var recentlyAddedAlbums: [Album] = []

    private let recentColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var recentAlbumsRequest: AlbumBrowseRequest {
        AlbumBrowseRequest(albums: library.albums, songs: library.songs, facts: library.browseFacts, lastPlayed: [:], query: "", sort: .recentlyAdded)
    }

    var body: some View {
        let visibleCategories = LibraryCategory.visible(order: storedOrder, hidden: hiddenSections)
        LibraryRootScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if case .available(let release) = releases.state {
                    Button { router.open(.settingsPage(.about)) } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(palette.primary)
                            Text("amp \(release.tag_name) \(L("is available"))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(palette.onSurface)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.onSurfaceVariant)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                .strokeBorder(palette.outline.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, Spacing.sm)
                }
                if visibleCategories.isEmpty {
                    Text(L(LibraryCustomizationText.empty)).foregroundStyle(.secondary).padding(.horizontal, Spacing.gutter)
                    Button(L(LibraryCustomizationText.action), action: customize).padding(.horizontal, Spacing.gutter)
                }
                ForEach(visibleCategories) { category in
                    VStack(spacing: 0) {
                        Button { router.open(category == .songs ? .allSongs : .category(category)) } label: {
                            HStack(spacing: Spacing.lg) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundStyle(palette.onSurface)
                                    .frame(width: 30)
                                Text(L(category.title))
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(palette.onSurface)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.onSurfaceVariant.opacity(0.6))
                            }
                            .frame(minHeight: 50)
                            .padding(.horizontal, Spacing.gutter)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("libraryCategory.\(category.rawValue)")
                        Rectangle()
                            .fill(palette.outline.opacity(0.22))
                            .frame(height: 0.5)
                            .padding(.leading, Spacing.gutter + 30 + Spacing.lg)
                            .padding(.trailing, Spacing.gutter)
                    }
                }
                if !recentlyAddedAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(L("Recently Added"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(palette.onSurface)
                            .padding(.horizontal, Spacing.gutter)
                        LazyVGrid(columns: recentColumns, spacing: 18) {
                            ForEach(recentlyAddedAlbums) { album in
                                Button { router.open(.album(album.id)) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Color.clear
                                            .aspectRatio(1, contentMode: .fit)
                                            .overlay { AlbumArtworkView(albumId: album.id, maxPixels: 500) }
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .padding(.bottom, 3)
                                        Text(CollectionDisplayTitle.normalized(album.title))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(palette.onSurface)
                                            .lineLimit(1)
                                        Text(album.artist)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(palette.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .pressable()
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                    }
                    .padding(.top, Spacing.xl)
                }
            }.padding(.vertical, Spacing.sm)
        }
        .refreshable { library.scan() }
        .task(id: recentAlbumsRequest) {
            let snapshot = recentAlbumsRequest
            let sorted = await Task.detached(priority: .userInitiated) {
                Array(snapshot.results().prefix(24))
            }.value
            guard !Task.isCancelled else { return }
            recentlyAddedAlbums = sorted
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Import music"), systemImage: "plus") { router.showsImporter = true }
                    Button(L("Wi-Fi Transfer"), systemImage: "wifi") { router.open(Tool.wifiTransfer) }
                    Button(L(LibraryCustomizationText.action), systemImage: "slider.horizontal.3", action: customize)
                        .accessibilityIdentifier("customizeLibrary")
                } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44) }
                .accessibilityLabel(L("Library options"))
            }
        }
        .sheet(isPresented: $showsOrder) { LibraryCustomizationView().preferredColorScheme(themeScheme) }
    }

    private func customize() { showsOrder = true }
}

struct LibraryShelfView: View {
    let shelf: LibraryShelf
    @ViewBuilder var body: some View {
        switch shelf {
        case .favorites: AllSongsView(category: .favorites)
        case .artists: EntityCategoryView(category: .artists)
        case .playlists: EntityCategoryView(category: .playlists)
        }
    }
}

/// A plain list of tracks that plays from the tapped one.
struct SongList: View {
    let songs: [Song]
    var emptyMessage = ""
    var emptyIcon = "music.note"
    var origin: CollectionRef?
    var showTrackNumbers = false
    var source: PlaybackSource?
    var selection: Binding<Set<Int64>>? = nil
    var showsFileDetails = false
    var onPlay: (() -> Void)? = nil
    var onPlaySong: ((Song) -> Void)? = nil
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        let songActions = router.songActions(actions, source: source ?? origin.map { PlaybackSource($0) })
        let currentId = player.state.currentSong?.id
        LazyVStack(spacing: 0) {
            if songs.isEmpty {
                EmptyState(message: emptyMessage, systemImage: emptyIcon)
            }
            ForEach(Array(songs.enumerated()), id: \.element.listScrollAnchor) { index, song in
                VStack(spacing: 0) {
                    if let selection {
                        Button {
                            if selection.wrappedValue.contains(song.id) { selection.wrappedValue.remove(song.id) }
                            else { selection.wrappedValue.insert(song.id) }
                        } label: {
                            HStack(spacing: 0) {
                                Image(systemName: selection.wrappedValue.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                    .frame(width: 44, height: 44)
                                TrackRow(song: song, isCurrent: song.id == currentId, showsFileDetails: showsFileDetails, showsActions: false, actions: songActions, onTap: {})
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SongRowText.accessibilityLabel(song, includingFileDetails: showsFileDetails))
                        .accessibilityValue(selection.wrappedValue.contains(song.id) ? "Selected" : "Not selected")
                    } else {
                        TrackRow(song: song, isCurrent: song.id == currentId, showTrackNumber: showTrackNumbers, displayTrackNumber: showTrackNumbers ? index + 1 : nil, showsFileDetails: showsFileDetails, actions: songActions) {
                            onPlay?()
                            onPlaySong?(song)
                            if player.state.currentSong?.id != song.id {
                                actions.play(songs, startIndex: index, origin: origin, source: source)
                            } else if !player.state.isPlaying {
                                player.play()
                            }
                            router.openPlayer()
                        }
                    }
                }
                .modifier(PlayerRevealedSong(songID: song.id))
                .id(song.listScrollAnchor)
            }
        }
        .scrollTargetLayout()
    }
}
