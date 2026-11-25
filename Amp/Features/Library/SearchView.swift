import SwiftUI
import Observation
import UIKit

/// A recently opened search result.
enum RecentSearchItem: Identifiable, Equatable {
    case song(Song)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .song(let song): "song:\(song.id)"
        case .album(let album): "album:\(album.id)"
        case .artist(let artist): "artist:\(artist.id)"
        case .playlist(let playlist): "playlist:\(playlist.id)"
        }
    }
}

/// Library search (title / artist / album, accent- and case-insensitive) and its recent items.
@MainActor
@Observable
final class SearchStore {
    static let sectionLimit = 20
    private static let recentLimit = 15

    var query = "" {
        didSet { schedule() }
    }
    private(set) var songs: [Song] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var topCategory: SearchTopCategory = .songs
    var type: SearchType = .all
    var selecting = false
    var selected = Set<Int64>()
    private(set) var extras = LibrarySearchExtras()
    private(set) var recents: [RecentSearchItem] = []

    private let library: LibraryStore
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var cachedIndex: LibrarySearchIndex?

    init(library: LibraryStore) { self.library = library }

    private func schedule() {
        pending?.cancel()
        if query.trimmed.isEmpty {
            generation &+= 1
            songs = []
            albums = []
            artists = []
            extras = LibrarySearchExtras()
            topCategory = .songs
            return
        }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(30))
            if !Task.isCancelled { await run() }
        }
    }

    func warmIndex() async {
        let revision = library.contentRevision
        if cachedIndex?.revision == revision { return }
        let songs = library.songs, albums = library.albums, artists = library.artists
        let albumArtists = library.albumArtists, playlists = library.playlists
        let built = await Task.detached(priority: .userInitiated) {
            LibrarySearchIndex(
                revision: revision,
                songs: songs,
                albums: albums,
                artists: artists,
                albumArtists: albumArtists,
                playlists: playlists
            )
        }.value
        guard !Task.isCancelled, library.contentRevision == revision else { return }
        cachedIndex = built
    }

    func run() async {
        generation &+= 1
        let request = generation
        let text = query.trimmed
        guard !text.isEmpty else {
            songs = []; albums = []; artists = []; extras = LibrarySearchExtras(); topCategory = .songs
            return
        }
        let revision = library.contentRevision
        let existingIndex = cachedIndex?.revision == revision ? cachedIndex : nil
        let songs = library.songs, albums = library.albums, artists = library.artists
        let albumArtists = library.albumArtists, playlists = library.playlists
        let result = await Task.detached(priority: .userInitiated) {
            let index = existingIndex ?? LibrarySearchIndex(
                revision: revision,
                songs: songs,
                albums: albums,
                artists: artists,
                albumArtists: albumArtists,
                playlists: playlists
            )
            let prepared = PreparedSearchQuery(text)
            return (
                index,
                LibrarySearch.results(prepared, index: index),
                LibrarySearchExtras.matching(prepared, index: index)
            )
        }.value
        guard !Task.isCancelled, request == generation, text == query.trimmed else { return }
        if result.0.revision == library.contentRevision {
            cachedIndex = result.0
        }
        self.songs = result.1.songs
        self.albums = result.1.albums
        self.artists = result.1.artists
        self.topCategory = result.1.topCategory
        extras = result.2
    }

    func remember(_ item: RecentSearchItem) {
        SearchHistoryStore.shared.remember(query, in: "library")
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        recents = Array(recents.prefix(Self.recentLimit))
    }

    func forget(_ item: RecentSearchItem) { recents.removeAll { $0.id == item.id } }

    func clearRecents() { recents = [] }
}

/// Search over the library: artists, albums and songs as you type, recent items before you do.
struct SearchView: View {
    @Environment(SearchStore.self) private var search
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var actions
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @AppStorage("library.search.sort") private var sort = "relevance"
    @State private var playlistMatchSongIDs: Set<Int64> = []
    @State private var artistMatchSongIDs: Set<Int64> = []

    private var matchingSongs: [Song] {
        let tracks: [Song]
        switch search.type {
        case .all, .songs: tracks = search.songs
        case .albums:
            let ids = Set(search.albums.map(\.id)); tracks = library.songs.filter { ids.contains($0.albumId) }
        case .artists:
            let ids = Set(search.artists.map(\.id))
            tracks = library.songs.filter { ids.contains($0.artistId) || artistMatchSongIDs.contains($0.id) }
        case .albumArtists:
            let ids = search.extras.albumArtists.reduce(into: Set<Int64>()) { $0.formUnion(library.albumArtistAlbums[$1.id] ?? []) }
            tracks = library.songs.filter { ids.contains($0.albumId) }
        case .folders:
            let paths = Set(search.extras.folders); tracks = library.songs.filter { paths.contains(($0.path as NSString).deletingLastPathComponent) }
        case .playlists:
            tracks = library.songs.filter { playlistMatchSongIDs.contains($0.id) }
        }
        guard let order = LibrarySort(rawValue: sort) else { return tracks }
        return SongBrowseRequest(songs: tracks, facts: library.browseFacts, query: "", sort: order).results()
    }

    private var hasEntityResults: Bool {
        (includes(.artists) && !search.artists.isEmpty)
            || (includes(.albums) && !search.albums.isEmpty)
            || (includes(.albumArtists) && !search.extras.albumArtists.isEmpty)
            || (includes(.playlists) && !search.extras.playlists.isEmpty)
            || (includes(.folders) && !search.extras.folders.isEmpty)
    }

    var body: some View {
        @Bindable var search = search
        let tracks = matchingSongs
        let playlistIDs = search.extras.playlists.map(\.id)
        let artistIDs = search.artists.map(\.id)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(SearchType.allCases) { type in
                            Button { search.type = type } label: {
                                Text(L(type.rawValue)).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, Spacing.md).frame(minHeight: 44)
                                    .background(.primary.opacity(search.type == type ? 0.16 : 0.04), in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(search.type == type ? .isSelected : [])
                                .accessibilityIdentifier("searchType.\(type.id)")
                        }
                    }.padding(.horizontal, Spacing.gutter)
                }
                CategoryHeader(title: "Search", icon: "magnifyingglass", count: tracks.count, selecting: search.selecting,
                               shuffle: { dismissKeyboard(); rememberQuery(); playSearchResults(tracks, shuffled: true) },
                               play: { dismissKeyboard(); rememberQuery(); playSearchResults(tracks, shuffled: false) },
                               search: { focused = true },
                               select: { search.selecting.toggle(); if !search.selecting { search.selected.removeAll() } }, options: {
                    Picker(L("Sort by"), selection: $sort) {
                        Text(L("Relevance")).tag("relevance")
                        ForEach(LibrarySort.songs, id: \.rawValue) { Text(L($0.label)).tag($0.rawValue) }
                    }
                }, showsTitle: false)
                if search.selecting { SongSelectionBar(songs: tracks, selected: $search.selected) }
                if search.query.trimmed.isEmpty {
                    RecentSearchesView(scope: "library") { search.query = $0; focused = true }
                        .padding(.horizontal, Spacing.gutter)
                    if !search.recents.isEmpty || SearchHistoryStore.shared.entries("library").isEmpty { recents }
                } else {
                    let songsFirst = !search.selecting && search.type == .all && search.topCategory == .songs && !tracks.isEmpty
                    if songsFirst {
                        let previewLimit = 6
                        let showsPreview = hasEntityResults && tracks.count > previewLimit
                        let visibleTracks = showsPreview ? Array(tracks.prefix(previewLimit)) : tracks
                        if hasEntityResults {
                            HStack {
                                Text(L("Songs")).font(.title3.weight(.bold))
                                Spacer()
                                if showsPreview {
                                    Button(L("See all")) {
                                        dismissKeyboard()
                                        search.type = .songs
                                    }
                                    .font(.subheadline.weight(.medium))
                                }
                            }
                            .padding(.horizontal, Spacing.gutter)
                        }
                        SongList(songs: visibleTracks, emptyMessage: L("No songs match this search."), emptyIcon: "magnifyingglass",
                                 selection: nil, showsFileDetails: true,
                                 continuousFromSearch: true,
                                 onPlay: { dismissKeyboard(); rememberQuery() },
                                 onPlaySong: { dismissKeyboard(); search.remember(.song($0)) })
                        entityResults
                    } else {
                        if !search.selecting { entityResults }
                        if search.selecting || search.type == .all || search.type == .songs {
                            SongList(songs: tracks, emptyMessage: L("No songs match this search."), emptyIcon: "magnifyingglass",
                                     selection: search.selecting ? $search.selected : nil, showsFileDetails: true,
                                     continuousFromSearch: true,
                                     onPlay: { dismissKeyboard(); rememberQuery() },
                                     onPlaySong: { dismissKeyboard(); search.remember(.song($0)) })
                        } else if tracks.isEmpty && !hasEntityResults {
                            EmptyState(message: L("No results for this filter."), systemImage: "magnifyingglass")
                        }
                    }
                }
            }.padding(.vertical, Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassSearchField(text: $search.query, prompt: L("Search your library"), focused: $focused,
                             close: { dismissKeyboard(); router.activate(.library) })
                .padding(.horizontal, Spacing.gutter).padding(.vertical, Spacing.sm)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = router.section == .search && !router.showsNowPlaying }
        .onChange(of: router.section) { _, section in focused = section == .search && !router.showsNowPlaying }
        .onChange(of: router.scrollToTopRequests[.search]) { _, _ in
            if router.section == .search && !router.showsNowPlaying { focused = true }
        }
        .onChange(of: router.showsNowPlaying) { _, shown in if shown { dismissKeyboard() } }
        .onChange(of: search.type) { _, _ in search.selected.removeAll() }
        .task(id: library.contentRevision) {
            await search.warmIndex()
            if !search.query.trimmed.isEmpty { await search.run() }
        }
        .task(id: playlistIDs) {
            guard !playlistIDs.isEmpty else { playlistMatchSongIDs = []; return }
            let database = library.database
            let loaded = await Task.detached(priority: .userInitiated) {
                Set(playlistIDs.flatMap { (try? database.playlistEntries($0))?.map(\.song.id) ?? [] })
            }.value
            guard !Task.isCancelled else { return }
            playlistMatchSongIDs = loaded
        }
        .task(id: artistIDs) {
            guard !artistIDs.isEmpty else { artistMatchSongIDs = []; return }
            let database = library.database
            let loaded = await Task.detached(priority: .userInitiated) {
                let byArtist = (try? database.artistSongIDs()) ?? [:]
                return artistIDs.reduce(into: Set<Int64>()) { $0.formUnion(byArtist[$1] ?? []) }
            }.value
            guard !Task.isCancelled else { return }
            artistMatchSongIDs = loaded
        }
        .modifier(ToolPageAppearance())
    }

    private func dismissKeyboard() {
        focused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func rememberQuery() { SearchHistoryStore.shared.remember(search.query, in: "library") }
    private func includes(_ type: SearchType) -> Bool { search.type == .all || search.type == type }

    @ViewBuilder private var entityResults: some View {
        if includes(.artists), !search.artists.isEmpty {
            Shelf(title: L("Artists")) {
                ForEach(search.artists) { artist in ArtistTile(artist: artist) { open(.artist(artist)) }.frame(width: 112) }
            }
        }
        if includes(.albums), !search.albums.isEmpty {
            Shelf(title: L("Albums")) {
                ForEach(search.albums) { album in AlbumTile(album: album) { open(.album(album)) }.frame(width: 128) }
            }
        }
        if includes(.albumArtists), !search.extras.albumArtists.isEmpty {
            Shelf(title: L("Album Artists")) {
                ForEach(search.extras.albumArtists) { artist in ArtistTile(artist: artist) { open(.artist(artist)) }.frame(width: 112) }
            }
        }
        if includes(.playlists), !search.extras.playlists.isEmpty {
            Shelf(title: L("Playlists")) {
                ForEach(search.extras.playlists) { playlist in PlaylistTile(playlist: playlist) { open(.playlist(playlist)) }.frame(width: 128) }
            }
        }
        if includes(.folders), !search.extras.folders.isEmpty {
            SectionHeading(title: L("Folders"))
            ForEach(search.extras.folders, id: \.self) { path in
                Button {
                    dismissKeyboard(); rememberQuery(); router.open(.songFolder(path))
                } label: {
                    Label(path.isEmpty ? L("Music folder") : path, systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, Spacing.gutter)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var recents: some View {
        if search.recents.isEmpty {
            EmptyState(message: L("Search your songs, albums and artists."), systemImage: "magnifyingglass")
        } else {
            HStack {
                Text(L("Recent")).font(.title3.weight(.bold))
                Spacer()
                Button(L("Clear")) { search.clearRecents() }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
            ForEach(search.recents) { item in
                HStack(spacing: Spacing.md) {
                    Button { reopen(item) } label: { recentRow(item) }.buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { search.forget(item) } label: {
                        Image(systemName: "xmark").foregroundStyle(.secondary).frame(width: 32, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from recent")
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    private func recentRow(_ item: RecentSearchItem) -> some View {
        HStack(spacing: Spacing.md) {
            Group {
                switch item {
                case .song(let song): SongArtworkView(song: song, maxPixels: 144)
                case .album(let album): AlbumArtworkView(albumId: album.id, maxPixels: 144)
                case .artist(let artist): ArtistArtworkView(artist: artist, fontSize: 18)
                case .playlist(let playlist): PlaylistCoverView(playlist: playlist)
                }
            }
            .frame(width: ArtworkSize.list, height: ArtworkSize.list)
            .clipShape(itemShape(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item)).font(.body.weight(.semibold)).lineLimit(1)
                Text(subtitle(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: ArtworkSize.list)
        .contentShape(Rectangle())
    }

    private func itemShape(_ item: RecentSearchItem) -> AnyShape {
        if case .artist = item { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private func title(_ item: RecentSearchItem) -> String {
        switch item {
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.name
        }
    }

    private func subtitle(_ item: RecentSearchItem) -> String {
        switch item {
        case .song(let song): "Song · \(song.artist)"
        case .album(let album): "Album · \(album.artist)"
        case .artist: "Artist"
        case .playlist(let playlist): "Playlist · \(countLabel(playlist.songCount, "song"))"
        }
    }

    private func playSearchResults(_ tracks: [Song], shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        if settings.continuousPlayback {
            let picked = shuffled ? tracks.randomElement()! : tracks[0]
            player.setShuffleModeEnabled(shuffled)
            let resolved = ContinuousPlayback.queue(startingAt: picked, allSongs: library.songs, facts: library.browseFacts)
            actions.play(resolved.songs, startIndex: resolved.startIndex, origin: nil, source: .library)
        } else if shuffled {
            actions.playShuffled(tracks)
        } else {
            actions.playInOrder(tracks)
        }
    }

    private func reopen(_ item: RecentSearchItem) {
        switch item {
        case .song(let song):
            dismissKeyboard()
            search.remember(item)
            if settings.continuousPlayback {
                let resolved = ContinuousPlayback.queue(startingAt: song, allSongs: library.songs, facts: library.browseFacts)
                actions.play(resolved.songs, startIndex: resolved.startIndex, origin: nil, source: .library)
            } else {
                actions.play([song], startIndex: 0)
            }
            router.openPlayer()
        default:
            open(item)
        }
    }

    private func open(_ item: RecentSearchItem) {
        dismissKeyboard()
        search.remember(item)
        switch item {
        case .album(let album): router.open(.album(album.id))
        case .artist(let artist): router.open(.artist(artist.id))
        case .playlist(let playlist): router.open(.playlist(playlist.id))
        case .song: break
        }
    }
}
